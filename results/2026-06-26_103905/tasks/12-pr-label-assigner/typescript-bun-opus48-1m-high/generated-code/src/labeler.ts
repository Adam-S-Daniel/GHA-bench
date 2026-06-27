/**
 * pr-label-assigner — core logic.
 *
 * Given a list of changed file paths (a PR's diff) and a set of
 * path-to-label mapping rules, compute the final set of labels.
 *
 * Features:
 *   - Glob patterns (via Bun.Glob): `docs/**`, `src/api/**`, `*.test.*`
 *   - Multiple labels per file (a file may match many rules)
 *   - Multiple files contribute to one shared label set
 *   - Priority ordering so the output is deterministic when rules "conflict"
 *     (i.e. when several rules contribute different labels): higher priority
 *     labels are emitted first.
 */

/** A single path-to-label mapping rule. */
export interface Rule {
  /** Glob pattern matched against changed file paths. */
  pattern: string;
  /** Label applied to the PR when at least one file matches `pattern`. */
  label: string;
  /**
   * Higher numbers rank earlier in the output. Defaults to 0.
   * Used to break ties / impose a stable conflict ordering.
   */
  priority?: number;
}

/**
 * Determine whether a single file path matches a single glob pattern.
 *
 * Uses Bun's built-in `Bun.Glob` for standard glob semantics:
 *   - `*`  matches any run of characters except `/`
 *   - `**` matches across directory separators
 *
 * Convenience: when a pattern contains no `/` (e.g. `*.test.*`), we also try
 * matching it against the file's basename. This lets short patterns target
 * files at any depth, matching the intuitive expectation in the task spec
 * (`*.test.*` -> tests, regardless of which folder the test lives in).
 */
export function matchesPattern(filePath: string, pattern: string): boolean {
  const glob = new Bun.Glob(pattern);
  if (glob.match(filePath)) return true;

  if (!pattern.includes("/")) {
    const basename = filePath.split("/").pop() ?? filePath;
    return glob.match(basename);
  }
  return false;
}

/**
 * Compute the final, ordered, de-duplicated set of labels for a PR.
 *
 * Ordering rules (deterministic):
 *   1. By the highest priority among the rules that produced the label (desc).
 *   2. Ties broken by label name (ascending) for stable, predictable output.
 *
 * @param files Changed file paths (the mocked PR file list).
 * @param rules Path-to-label mapping rules.
 * @returns Unique labels, ordered by priority then name.
 */
export function assignLabels(files: string[], rules: Rule[]): string[] {
  if (!Array.isArray(files)) {
    throw new TypeError("assignLabels: `files` must be an array of strings");
  }
  if (!Array.isArray(rules)) {
    throw new TypeError("assignLabels: `rules` must be an array of rules");
  }

  // Track, for each matched label, the strongest priority that produced it so
  // that conflicting rules order predictably.
  const labelPriority = new Map<string, number>();

  for (const rule of rules) {
    if (typeof rule?.pattern !== "string" || typeof rule?.label !== "string") {
      throw new TypeError(
        `assignLabels: each rule needs string \`pattern\` and \`label\` (got ${JSON.stringify(
          rule,
        )})`,
      );
    }
    const priority = rule.priority ?? 0;
    const matched = files.some((file) => matchesPattern(file, rule.pattern));
    if (!matched) continue;

    const existing = labelPriority.get(rule.label);
    if (existing === undefined || priority > existing) {
      labelPriority.set(rule.label, priority);
    }
  }

  return [...labelPriority.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([label]) => label);
}

/**
 * Parse a JSON configuration document into a validated list of rules.
 *
 * Expected shape:
 *   { "rules": [ { "pattern": "docs/**", "label": "documentation", "priority": 1 }, ... ] }
 *
 * Throws clear, actionable errors for malformed input so CI failures are easy
 * to diagnose.
 */
export function parseConfig(jsonText: string): Rule[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new SyntaxError(`parseConfig: invalid JSON config — ${reason}`);
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new TypeError("parseConfig: config root must be a JSON object");
  }

  const rules = (parsed as { rules?: unknown }).rules;
  if (!Array.isArray(rules)) {
    throw new TypeError(
      "parseConfig: config must contain a `rules` array (e.g. { \"rules\": [...] })",
    );
  }

  return rules.map((rule, i) => {
    if (typeof rule !== "object" || rule === null) {
      throw new TypeError(`parseConfig: rule at index ${i} must be an object`);
    }
    const { pattern, label, priority } = rule as Record<string, unknown>;
    if (typeof pattern !== "string") {
      throw new TypeError(
        `parseConfig: rule at index ${i} is missing a string \`pattern\``,
      );
    }
    if (typeof label !== "string") {
      throw new TypeError(
        `parseConfig: rule at index ${i} is missing a string \`label\``,
      );
    }
    if (priority !== undefined && typeof priority !== "number") {
      throw new TypeError(
        `parseConfig: rule at index ${i} has a non-numeric \`priority\``,
      );
    }
    return priority === undefined
      ? { pattern, label }
      : { pattern, label, priority };
  });
}
