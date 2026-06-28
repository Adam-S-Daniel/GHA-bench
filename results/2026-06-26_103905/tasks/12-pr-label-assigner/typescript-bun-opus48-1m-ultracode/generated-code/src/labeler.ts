// Core logic for the PR label assigner.
//
// Approach: a PR is represented as a flat list of changed file paths. A config
// declares a set of rules, each mapping one label to one or more glob patterns.
// We match every file against every rule, collect the resulting labels, resolve
// conflicts between mutually-exclusive rules by priority, then emit the final
// ordered label set.
//
// Globbing is delegated to Bun's built-in `Bun.Glob` (no third-party deps), so
// the semantics are standard: `*` matches within a path segment, `**` matches
// across segments. See `matchPattern` for the one ergonomic addition.

import { Glob } from "bun";
import { readFileSync } from "node:fs";

/** A single label-assignment rule. */
export interface LabelRule {
  /** The label applied to a PR when any of `patterns` match a changed file. */
  label: string;
  /** Glob patterns that select files for this label. */
  patterns: string[];
  /**
   * Conflict-resolution weight. Higher wins. Used for two things:
   *  - ordering the final label set (descending), and
   *  - picking a single winner among rules that share a `group`.
   * Defaults to 0.
   */
  priority?: number;
  /**
   * Optional mutual-exclusion group name. When several rules in the same group
   * match the *same file*, only the highest-priority rule contributes its label
   * for that file (ties broken by declaration order). Rules without a group are
   * always additive — that is how a file gets "multiple labels".
   */
  group?: string;
}

/** Top-level configuration: just an ordered list of rules. */
export interface LabelerConfig {
  rules: LabelRule[];
}

/** Result of assigning labels to a set of changed files. */
export interface LabelResult {
  /** The final, de-duplicated label set, ordered by priority then name. */
  labels: string[];
  /** Per-file breakdown: which labels each changed file contributed. */
  byFile: Record<string, string[]>;
}

/**
 * Match a single glob `pattern` against a single `path`.
 *
 * Standard glob semantics via `Bun.Glob`, with one ergonomic rule: a pattern
 * that contains no `/` is treated as a *basename* matcher and is also tested
 * against the file's basename. This makes intuitive rules like `*.test.*` or
 * `*.md` match files anywhere in the tree (e.g. `src/components/foo.test.tsx`),
 * which is what users expect from a labeler. Patterns that contain a `/` are
 * anchored to the full path with no basename fallback.
 *
 * @throws if `pattern` is empty/whitespace — an empty glob is always a config bug.
 */
export function matchPattern(pattern: string, path: string): boolean {
  if (typeof pattern !== "string" || pattern.trim() === "") {
    throw new Error(`Invalid glob pattern: patterns must be non-empty strings, got ${JSON.stringify(pattern)}`);
  }

  let glob: Glob;
  try {
    glob = new Glob(pattern);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid glob pattern ${JSON.stringify(pattern)}: ${message}`);
  }

  if (glob.match(path)) {
    return true;
  }

  // Basename fallback for slash-free patterns (e.g. `*.test.*`).
  if (!pattern.includes("/")) {
    const basename = path.split("/").pop() ?? path;
    if (basename !== path && glob.match(basename)) {
      return true;
    }
  }

  return false;
}

/** True if any of `rule`'s patterns match `path`. */
function ruleMatchesFile(rule: LabelRule, path: string): boolean {
  return rule.patterns.some((pattern) => matchPattern(pattern, path));
}

/** Effective priority of a rule (default 0). */
function priorityOf(rule: LabelRule): number {
  return rule.priority ?? 0;
}

/**
 * Assign labels to a PR given its `files` (changed paths) and a `config`.
 *
 * Algorithm:
 *  1. For each file, find every rule that matches it.
 *  2. Resolve per-file group conflicts: within each mutual-exclusion `group`,
 *     keep only the single highest-priority matching rule (ties → earliest in
 *     config). Rules without a group are always kept (this is how a file ends
 *     up with multiple labels).
 *  3. Record each file's labels (ordered by priority desc, then name) in
 *     `byFile`, and union all labels into the final set.
 *  4. Order the final set by the maximum priority seen for each label
 *     (descending), then alphabetically for stable, predictable output.
 */
export function assignLabels(files: string[], config: LabelerConfig): LabelResult {
  if (!Array.isArray(files)) {
    throw new Error("assignLabels: `files` must be an array of path strings");
  }

  const byFile: Record<string, string[]> = {};
  // Track the best (max) priority observed for each emitted label, for ordering.
  const labelPriority = new Map<string, number>();

  for (const file of files) {
    // Index matching rules by their original position so ties are deterministic.
    const matches = config.rules
      .map((rule, index) => ({ rule, index }))
      .filter(({ rule }) => ruleMatchesFile(rule, file));

    // Step 2: per-file group conflict resolution.
    const groupWinners = new Map<string, { rule: LabelRule; index: number }>();
    const kept: { rule: LabelRule; index: number }[] = [];
    for (const match of matches) {
      const group = match.rule.group;
      if (group === undefined) {
        kept.push(match); // ungrouped rules are always additive
        continue;
      }
      const current = groupWinners.get(group);
      if (
        current === undefined ||
        priorityOf(match.rule) > priorityOf(current.rule) ||
        // tie → keep the earliest-declared rule
        (priorityOf(match.rule) === priorityOf(current.rule) && match.index < current.index)
      ) {
        groupWinners.set(group, match);
      }
    }
    kept.push(...groupWinners.values());

    // Step 3: order this file's labels and record them.
    const fileLabels = kept
      .slice()
      .sort((a, b) => comparePriorityThenName(a.rule, b.rule))
      .map((m) => m.rule.label);
    byFile[file] = dedupe(fileLabels);

    for (const match of kept) {
      const prev = labelPriority.get(match.rule.label);
      const prio = priorityOf(match.rule);
      if (prev === undefined || prio > prev) {
        labelPriority.set(match.rule.label, prio);
      }
    }
  }

  // Step 4: order the final, unioned label set.
  const labels = [...labelPriority.keys()].sort((a, b) => {
    const pa = labelPriority.get(a)!;
    const pb = labelPriority.get(b)!;
    if (pa !== pb) return pb - pa; // higher priority first
    return a < b ? -1 : a > b ? 1 : 0; // then alphabetical
  });

  return { labels, byFile };
}

/** Sort comparator: higher priority first, then label name ascending. */
function comparePriorityThenName(a: LabelRule, b: LabelRule): number {
  const pa = priorityOf(a);
  const pb = priorityOf(b);
  if (pa !== pb) return pb - pa;
  return a.label < b.label ? -1 : a.label > b.label ? 1 : 0;
}

/** Stable de-duplication preserving first-seen order. */
function dedupe(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const value of values) {
    if (!seen.has(value)) {
      seen.add(value);
      out.push(value);
    }
  }
  return out;
}

/**
 * Validate an untrusted, parsed config value and narrow it to `LabelerConfig`.
 *
 * Every failure throws an `Error` whose message points at the offending rule
 * (by index, and by label once known) so a misconfigured `.json` is easy to
 * fix. This is the single chokepoint all config must pass through.
 */
export function validateConfig(raw: unknown): LabelerConfig {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error(
      `Invalid config: config must be an object with a "rules" array, got ${describeType(raw)}`,
    );
  }

  const rules = (raw as Record<string, unknown>).rules;
  if (!Array.isArray(rules)) {
    throw new Error('Invalid config: config must contain a "rules" array');
  }

  const validated: LabelRule[] = rules.map((rule, index) => {
    if (typeof rule !== "object" || rule === null || Array.isArray(rule)) {
      throw new Error(`Invalid config: rule at index ${index} must be an object`);
    }
    const r = rule as Record<string, unknown>;

    if (typeof r.label !== "string" || r.label.trim() === "") {
      throw new Error(`Invalid config: rule at index ${index} must have a non-empty "label" string`);
    }
    const label = r.label;

    if (!Array.isArray(r.patterns) || r.patterns.length === 0) {
      throw new Error(`Invalid config: rule "${label}" must have a non-empty "patterns" array`);
    }
    for (const pattern of r.patterns) {
      if (typeof pattern !== "string" || pattern.trim() === "") {
        throw new Error(`Invalid config: rule "${label}" has a pattern that is not a non-empty string`);
      }
    }

    if (r.priority !== undefined && typeof r.priority !== "number") {
      throw new Error(`Invalid config: rule "${label}" has a "priority" that is not a number`);
    }
    if (r.group !== undefined && typeof r.group !== "string") {
      throw new Error(`Invalid config: rule "${label}" has a "group" that is not a string`);
    }

    const result: LabelRule = { label, patterns: r.patterns as string[] };
    if (r.priority !== undefined) result.priority = r.priority as number;
    if (r.group !== undefined) result.group = r.group as string;
    return result;
  });

  return { rules: validated };
}

/** Human-friendly type description for error messages. */
function describeType(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

/**
 * Read, parse, and validate a JSON config file at `path`.
 * Distinguishes "file not found" from "invalid JSON" from "invalid schema"
 * so the operator knows exactly what to fix.
 */
export function loadConfig(path: string): LabelerConfig {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`Config file not found: ${path}`);
    }
    throw new Error(`Could not read config file ${path}: ${(err as Error).message}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new Error(`Invalid JSON in config file ${path}: ${(err as Error).message}`);
  }

  return validateConfig(parsed);
}

/**
 * Read a changed-files list (one path per line). Blank lines and lines starting
 * with `#` are ignored, and surrounding whitespace is trimmed. This is the
 * mockable "PR's changed files" input.
 */
export function loadChangedFiles(path: string): string[] {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`Changed-files list not found: ${path}`);
    }
    throw new Error(`Could not read changed-files list ${path}: ${(err as Error).message}`);
  }

  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"));
}
