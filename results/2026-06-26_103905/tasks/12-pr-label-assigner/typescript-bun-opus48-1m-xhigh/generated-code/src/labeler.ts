/**
 * PR Label Assigner — core logic.
 *
 * Given a list of changed file paths and a set of configurable path-to-label
 * rules (using glob patterns), this module computes the final set of labels
 * that should be applied to a pull request.
 *
 * Design overview:
 *   - Glob matching is implemented by translating a glob pattern into an
 *     anchored regular expression (see `globToRegExp`). This keeps the
 *     semantics explicit and testable rather than depending on an external
 *     glob library.
 *   - A "rule" maps one label to one or more glob patterns and an optional
 *     priority. A file matches a rule if it matches ANY of the rule's patterns.
 *   - The final label set is the UNION of the labels of every rule that
 *     matched at least one changed file (so a single file can produce multiple
 *     labels, and a label can be produced by multiple files).
 *   - When several labels apply, PRIORITY controls their output order: higher
 *     priority first, ties broken by the rule's declaration order. This is the
 *     concrete meaning of "priority ordering when rules conflict".
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A single path-to-label rule. */
export interface LabelRule {
  /** The label to apply when any of `patterns` matches a changed file. */
  label: string;
  /** One or more glob patterns; a file matches the rule if ANY pattern hits. */
  patterns: string[];
  /**
   * Higher priority labels are emitted earlier in the output. When several
   * labels apply to a PR this determines their order ("priority ordering when
   * rules conflict"). Defaults to 0.
   */
  priority?: number;
}

/** The full labeler configuration: an ordered list of rules. */
export interface LabelerConfig {
  rules: LabelRule[];
}

/** The result of evaluating a config against a set of changed files. */
export interface LabelResult {
  /** Final, deduplicated label set, ordered by descending priority. */
  labels: string[];
  /** For each applied label, the sorted list of files that triggered it. */
  matches: Record<string, string[]>;
}

/** Extract the basename (last path segment) of a POSIX-style path. */
function basename(filePath: string): string {
  const idx = filePath.lastIndexOf("/");
  return idx === -1 ? filePath : filePath.slice(idx + 1);
}

/**
 * Translate a glob pattern into an anchored RegExp.
 *
 * Supported syntax:
 *   - double-star matches any sequence of characters, INCLUDING `/`
 *     (cross-directory).
 *   - single-star matches any sequence of characters EXCEPT `/` (within one
 *     path segment).
 *   - `?`   matches exactly one character that is not `/`.
 *   - a double-star immediately followed by a slash collapses to "zero or more
 *     directory segments", so a leading globstar matches both `foo` and
 *     `a/b/foo` and a trailing one (e.g. `src` + globstar) matches everything
 *     beneath that directory.
 *   - every other character is matched literally (regex metacharacters are
 *     escaped).
 *
 * The returned RegExp is anchored (`^...$`) so a pattern must match the whole
 * subject string, not just a substring.
 */
export function globToRegExp(glob: string): RegExp {
  let re = "";
  const chars = [...glob];

  for (let i = 0; i < chars.length; i++) {
    const c = chars[i]!;

    if (c === "*") {
      const isGlobstar = chars[i + 1] === "*";
      if (isGlobstar) {
        // Consume the second '*'.
        i++;
        // `**/` (globstar followed by a slash) means "zero or more leading
        // directory segments", so `**/foo` matches both `foo` and `a/b/foo`.
        if (chars[i + 1] === "/") {
          re += "(?:.*/)?";
          i++; // consume the slash too
        } else {
          // A trailing or bare `**` matches anything, slashes included.
          re += ".*";
        }
      } else {
        // A single `*` stays within a path segment.
        re += "[^/]*";
      }
    } else if (c === "?") {
      re += "[^/]";
    } else if ("\\^$.|+()[]{}".includes(c)) {
      // Escape regex metacharacters so they are treated literally.
      re += "\\" + c;
    } else {
      re += c;
    }
  }

  return new RegExp("^" + re + "$");
}

/**
 * Test whether a single glob pattern matches a file path.
 *
 * Convention: a pattern that contains NO `/` is matched against the file's
 * basename, so `*.test.*` matches `src/components/Button.test.tsx`. A pattern
 * that DOES contain a `/` (e.g. `docs/**`, `src/api/**`) is matched against the
 * full path. This mirrors how most labelers and `.gitignore`-style tools treat
 * slash-less patterns and makes the task's own examples behave as written.
 */
export function matchesGlob(pattern: string, filePath: string): boolean {
  if (pattern.length === 0) return false;
  const subject = pattern.includes("/") ? filePath : basename(filePath);
  return globToRegExp(pattern).test(subject);
}

// ---------------------------------------------------------------------------
// Rule evaluation
// ---------------------------------------------------------------------------

/**
 * Compute the final label set for a list of changed files.
 *
 * For every rule we collect the changed files that match any of its patterns.
 * A rule contributes its label iff at least one file matched. The returned
 * `labels` array is the deduplicated union of all contributing labels, ordered
 * by descending priority with ties broken by declaration order (so the output
 * order is deterministic and stable).
 */
export function assignLabels(
  config: LabelerConfig,
  files: string[],
): LabelResult {
  // Per-label accumulator. `firstIndex` is the declaration index of the first
  // rule producing this label and is used as a stable tie-breaker. `priority`
  // is the strongest (max) priority among rules that share the label.
  interface Acc {
    priority: number;
    firstIndex: number;
    files: Set<string>;
  }
  const accByLabel = new Map<string, Acc>();

  config.rules.forEach((rule, index) => {
    const priority = rule.priority ?? 0;
    // Files that match at least one of this rule's patterns.
    const matched = files.filter((file) =>
      rule.patterns.some((pattern) => matchesGlob(pattern, file)),
    );
    if (matched.length === 0) return;

    const existing = accByLabel.get(rule.label);
    if (existing) {
      existing.priority = Math.max(existing.priority, priority);
      existing.firstIndex = Math.min(existing.firstIndex, index);
      for (const f of matched) existing.files.add(f);
    } else {
      accByLabel.set(rule.label, {
        priority,
        firstIndex: index,
        files: new Set(matched),
      });
    }
  });

  // Order labels by descending priority, then ascending declaration order.
  const ordered = [...accByLabel.entries()].sort((a, b) => {
    if (b[1].priority !== a[1].priority) return b[1].priority - a[1].priority;
    return a[1].firstIndex - b[1].firstIndex;
  });

  const labels = ordered.map(([label]) => label);
  const matches: Record<string, string[]> = {};
  for (const [label, acc] of ordered) {
    // Sort the contributing files for stable, human-friendly output.
    matches[label] = [...acc.files].sort();
  }

  return { labels, matches };
}

// ---------------------------------------------------------------------------
// Configuration parsing & validation
// ---------------------------------------------------------------------------

/** Type guard for a plain JSON object. */
function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate untrusted JSON and turn it into a `LabelerConfig`.
 *
 * Accepts either:
 *   - `{ "rules": [ ... ] }`, or
 *   - a bare top-level array of rules `[ ... ]`.
 *
 * Throws an `Error` with a descriptive message (naming the offending rule and
 * index) when the structure is invalid, so the CLI can surface a useful
 * message instead of a cryptic crash.
 */
export function parseConfig(raw: unknown): LabelerConfig {
  // Normalize the two accepted shapes into a rules array.
  let rawRules: unknown;
  if (Array.isArray(raw)) {
    rawRules = raw;
  } else if (isObject(raw)) {
    rawRules = raw.rules;
  } else {
    throw new Error(
      'Invalid config: expected an object with a "rules" array, or a ' +
        "top-level array of rules.",
    );
  }

  if (!Array.isArray(rawRules)) {
    throw new Error(
      'Invalid config: "rules" must be an array of rule objects.',
    );
  }

  const rules: LabelRule[] = rawRules.map((rawRule, index) => {
    if (!isObject(rawRule)) {
      throw new Error(`Invalid rule at index ${index}: each rule must be an object.`);
    }

    const { label, patterns, priority } = rawRule;

    if (typeof label !== "string" || label.trim() === "") {
      throw new Error(
        `Invalid rule at index ${index}: "label" must be a non-empty string.`,
      );
    }

    if (
      !Array.isArray(patterns) ||
      patterns.length === 0 ||
      !patterns.every((p) => typeof p === "string" && p.length > 0)
    ) {
      throw new Error(
        `Invalid rule "${label}" at index ${index}: "patterns" must be a ` +
          "non-empty array of non-empty strings.",
      );
    }

    if (priority !== undefined && typeof priority !== "number") {
      throw new Error(
        `Invalid rule "${label}" at index ${index}: "priority" must be a number.`,
      );
    }

    return {
      label,
      patterns: patterns as string[],
      priority: (priority as number | undefined) ?? 0,
    };
  });

  return { rules };
}
