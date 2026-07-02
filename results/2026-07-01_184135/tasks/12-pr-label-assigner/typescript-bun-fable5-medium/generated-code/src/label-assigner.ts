/**
 * PR Label Assigner — core library.
 *
 * Given a list of changed file paths (as from a PR), applies labels based on
 * configurable path-to-label mapping rules with glob patterns, multiple
 * labels per rule, and priority ordering when rules conflict.
 */

/** Error thrown for invalid rule config or changed-file input. */
export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

/** A single path-to-label mapping rule. */
export interface LabelRule {
  /** Glob pattern matched against each changed file path. */
  pattern: string;
  /** Labels applied when the pattern matches (one rule → many labels). */
  labels: string[];
  /**
   * Conflict priority (default 0). When several rules match the same file,
   * only the rules sharing the highest priority contribute labels for it.
   */
  priority?: number;
}

/** Convert a glob pattern to an anchored RegExp.
 *
 * Supported syntax:
 *   `**` — any characters, including `/`
 *   `*`  — any characters, except `/`
 *   `?`  — one character, except `/`
 * All other characters are matched literally (regex metachars are escaped).
 */
export function globToRegExp(pattern: string): RegExp {
  let regex = "";
  let i = 0;
  while (i < pattern.length) {
    const ch = pattern[i]!;
    if (ch === "*") {
      if (pattern[i + 1] === "*") {
        regex += ".*"; // `**` crosses directory separators
        i += 2;
      } else {
        regex += "[^/]*"; // `*` stays within one path segment
        i += 1;
      }
    } else if (ch === "?") {
      regex += "[^/]";
      i += 1;
    } else {
      // Escape any regex metacharacter so it matches literally.
      regex += ch.replace(/[.+^${}()|[\]\\]/g, "\\$&");
      i += 1;
    }
  }
  return new RegExp(`^${regex}$`);
}

/** Test whether a file path matches a glob pattern.
 *
 * Patterns that contain no `/` are matched against the file's basename,
 * so `*.test.*` matches `src/utils/math.test.ts`.
 */
export function matchesGlob(pattern: string, filePath: string): boolean {
  const target = pattern.includes("/")
    ? filePath
    : (filePath.split("/").pop() ?? filePath);
  return globToRegExp(pattern).test(target);
}

/**
 * Validate untyped JSON into a LabelRule[].
 * Accepts either a bare array of rules or an object with a `rules` array.
 * Throws ConfigError with a message naming the offending rule (1-based).
 */
export function parseRules(raw: unknown): LabelRule[] {
  const arr =
    typeof raw === "object" && raw !== null && !Array.isArray(raw)
      ? (raw as Record<string, unknown>).rules
      : raw;
  if (!Array.isArray(arr)) {
    throw new ConfigError(
      'rules config must be an array of rules (or an object with a "rules" array)',
    );
  }
  return arr.map((entry, index) => {
    const where = `rule #${index + 1}`;
    if (typeof entry !== "object" || entry === null) {
      throw new ConfigError(`${where}: each rule must be an object`);
    }
    const rule = entry as Record<string, unknown>;
    if (typeof rule.pattern !== "string" || rule.pattern.length === 0) {
      throw new ConfigError(`${where}: "pattern" must be a non-empty string`);
    }
    if (
      !Array.isArray(rule.labels) ||
      rule.labels.length === 0 ||
      !rule.labels.every((l): l is string => typeof l === "string" && l !== "")
    ) {
      throw new ConfigError(
        `${where}: "labels" must be a non-empty array of strings`,
      );
    }
    if (rule.priority !== undefined) {
      if (typeof rule.priority !== "number" || !Number.isFinite(rule.priority)) {
        throw new ConfigError(`${where}: "priority" must be a finite number`);
      }
    }
    const parsed: LabelRule = { pattern: rule.pattern, labels: rule.labels };
    if (typeof rule.priority === "number") parsed.priority = rule.priority;
    return parsed;
  });
}

/** Validate untyped JSON into a changed-file path list. */
export function parseChangedFiles(raw: unknown): string[] {
  if (!Array.isArray(raw) || !raw.every((f) => typeof f === "string")) {
    throw new ConfigError("changed files must be an array of path strings");
  }
  return raw;
}

/**
 * Compute the final label set for a list of changed files.
 *
 * Per file: find all matching rules, keep only those at the highest
 * priority among the matches (conflict resolution), and collect their
 * labels. The result is the sorted, deduplicated union across all files.
 */
export function assignLabels(files: string[], rules: LabelRule[]): string[] {
  const labels = new Set<string>();
  for (const file of files) {
    const matching = rules.filter((rule) => matchesGlob(rule.pattern, file));
    if (matching.length === 0) continue;
    const top = Math.max(...matching.map((rule) => rule.priority ?? 0));
    for (const rule of matching) {
      if ((rule.priority ?? 0) === top) {
        for (const label of rule.labels) labels.add(label);
      }
    }
  }
  return [...labels].sort();
}
