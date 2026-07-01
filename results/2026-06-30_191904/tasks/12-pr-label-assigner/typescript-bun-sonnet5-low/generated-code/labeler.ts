// PR Label Assigner: maps a list of changed file paths to a set of labels
// based on configurable glob-pattern rules with priority-based conflict resolution.

/** A single path-to-label mapping rule. */
export interface LabelRule {
  /** Glob pattern (supports `**`, `*`, `?`) matched against a file path. */
  pattern: string;
  /** Label to apply when a file matches this rule's pattern. */
  label: string;
  /** Higher priority wins when `exclusive` mode resolves conflicts per file. */
  priority: number;
}

export interface AssignLabelsOptions {
  /**
   * When true, each file contributes only the label(s) of its
   * highest-priority matching rule(s), instead of every matching rule's label.
   */
  exclusive?: boolean;
}

/** Converts a glob pattern (with `**`, `*`, `?`) into a RegExp. */
function globToRegExp(pattern: string): RegExp {
  let regexSource = "";
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i];
    if (char === "*") {
      if (pattern[i + 1] === "*") {
        // `**` matches any sequence, including path separators.
        regexSource += ".*";
        i++;
      } else {
        // `*` matches any sequence except path separators.
        regexSource += "[^/]*";
      }
    } else if (char === "?") {
      regexSource += "[^/]";
    } else if (".+^${}()|[]\\".includes(char)) {
      regexSource += `\\${char}`;
    } else {
      regexSource += char;
    }
  }
  return new RegExp(`^${regexSource}$`);
}

function matchesPattern(filePath: string, pattern: string): boolean {
  // A pattern without a path separator (e.g. "*.test.*") matches against
  // the file's basename anywhere in the tree, not just at the root.
  const target = pattern.includes("/") ? filePath : filePath.split("/").pop() ?? filePath;
  return globToRegExp(pattern).test(target);
}

/**
 * Assigns labels to a list of changed file paths based on the provided rules.
 *
 * @param files - Changed file paths from a PR.
 * @param rules - Path-to-label mapping rules.
 * @param options - Optional conflict-resolution behavior.
 * @returns The deduplicated set of labels that apply, in no particular order.
 * @throws if `rules` is empty or any rule has an empty pattern/label.
 */
export function assignLabels(
  files: string[],
  rules: LabelRule[],
  options: AssignLabelsOptions = {},
): string[] {
  if (rules.length === 0) {
    throw new Error("No label rules provided");
  }
  for (const rule of rules) {
    if (!rule.pattern) {
      throw new Error("Rule has an empty pattern");
    }
    if (!rule.label) {
      throw new Error("Rule has an empty label");
    }
  }

  const labels = new Set<string>();

  for (const file of files) {
    const matchingRules = rules.filter((rule) => matchesPattern(file, rule.pattern));
    if (matchingRules.length === 0) continue;

    if (options.exclusive) {
      const highestPriority = Math.max(...matchingRules.map((r) => r.priority));
      for (const rule of matchingRules) {
        if (rule.priority === highestPriority) labels.add(rule.label);
      }
    } else {
      for (const rule of matchingRules) labels.add(rule.label);
    }
  }

  return Array.from(labels);
}
