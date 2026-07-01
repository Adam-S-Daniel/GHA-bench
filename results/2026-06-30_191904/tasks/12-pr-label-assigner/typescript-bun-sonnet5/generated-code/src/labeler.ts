// Core PR label-assignment logic: pure functions, no I/O.
// Kept separate from src/cli.ts so it can be unit-tested without touching
// the filesystem or process argv.

/** A single path-to-label mapping rule. */
export interface Rule {
  /** Glob pattern matched against changed file paths (e.g. "docs/**"). */
  pattern: string;
  /** Label to apply when at least one changed file matches `pattern`. */
  label: string;
  /**
   * Controls output ordering when several rules match (higher sorts first).
   * Defaults to 0. This is how "rule conflicts" — several distinct labels
   * being candidates at once — are resolved into one deterministic order.
   */
  priority?: number;
}

/**
 * Returns true when `filePath` matches `pattern`.
 * Uses Bun's built-in glob matcher (supports `*`, `**`, `?`, `{a,b}`, etc).
 *
 * Patterns with no "/" (e.g. `*.test.*`) are also matched against the file's
 * basename, so they apply at any directory depth rather than only at the
 * repo root — this matches the intuitive reading of a pattern like
 * `*.test.*` -> tests.
 */
export function matchesGlob(filePath: string, pattern: string): boolean {
  const glob = new Bun.Glob(pattern);
  if (glob.match(filePath)) return true;

  if (!pattern.includes("/")) {
    const basename = filePath.split("/").pop() ?? filePath;
    return glob.match(basename);
  }
  return false;
}

/**
 * Computes the de-duplicated, deterministically-ordered set of labels that
 * apply to a PR, given its changed files and the configured rules.
 *
 * - A file may match several rules, contributing several labels.
 * - A label is included once no matter how many files/rules produced it.
 * - When several rules match, the resulting labels are ordered by the
 *   highest `priority` among the rules that produced them (descending),
 *   with ties broken alphabetically by label name for stable output.
 */
export function assignLabels(files: string[], rules: Rule[]): string[] {
  if (!Array.isArray(files)) {
    throw new Error("assignLabels: `files` must be an array of file paths");
  }
  if (!Array.isArray(rules)) {
    throw new Error("assignLabels: `rules` must be an array of Rule objects");
  }

  const bestPriority = new Map<string, number>();
  for (const rule of rules) {
    if (!files.some((file) => matchesGlob(file, rule.pattern))) continue;
    const priority = rule.priority ?? 0;
    const current = bestPriority.get(rule.label);
    if (current === undefined || priority > current) {
      bestPriority.set(rule.label, priority);
    }
  }

  return [...bestPriority.entries()]
    .sort(([labelA, priorityA], [labelB, priorityB]) =>
      priorityB - priorityA || labelA.localeCompare(labelB),
    )
    .map(([label]) => label);
}

/**
 * Parses a JSON configuration document into a validated list of `Rule`s.
 *
 * Expected shape:
 *   { "rules": [ { "pattern": "docs/**", "label": "documentation", "priority": 1 }, ... ] }
 *
 * Throws a descriptive `Error` for any malformed input so CI failures point
 * directly at the problem (bad JSON, missing field, wrong type, etc.).
 */
export function parseConfig(jsonText: string): Rule[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`parseConfig: invalid JSON config — ${reason}`);
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("parseConfig: config root must be a JSON object");
  }

  const rulesValue = (parsed as { rules?: unknown }).rules;
  if (!Array.isArray(rulesValue)) {
    throw new Error(
      'parseConfig: config must contain a "rules" array, e.g. { "rules": [...] }',
    );
  }

  return rulesValue.map((rule, index) => {
    if (typeof rule !== "object" || rule === null) {
      throw new Error(`parseConfig: rules[${index}] must be an object`);
    }
    const { pattern, label, priority } = rule as Record<string, unknown>;

    if (typeof pattern !== "string" || pattern.length === 0) {
      throw new Error(
        `parseConfig: rules[${index}] is missing a non-empty string "pattern"`,
      );
    }
    if (typeof label !== "string" || label.length === 0) {
      throw new Error(
        `parseConfig: rules[${index}] is missing a non-empty string "label"`,
      );
    }
    if (priority !== undefined && typeof priority !== "number") {
      throw new Error(
        `parseConfig: rules[${index}] has a non-numeric "priority"`,
      );
    }

    return priority === undefined
      ? { pattern, label }
      : { pattern, label, priority };
  });
}

/**
 * Parses a newline-delimited changed-file list (the mocked PR diff) into an
 * array of file paths. Blank lines and `#`-prefixed comment lines are
 * ignored so fixtures can be annotated for readability.
 */
export function parseChangedFiles(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"));
}
