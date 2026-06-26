// Core label assignment logic.
//
// Given a list of changed file paths (a mocked PR diff) and a set of
// path-to-label rules, compute the final set of labels. Each rule maps a glob
// pattern to a label, with an optional priority used to order the resulting
// label set when several rules apply.
import { matchGlob } from "./glob.ts";

export interface LabelRule {
  /** Glob pattern matched against changed file paths (see ./glob.ts). */
  pattern: string;
  /** Label applied to files matching this pattern. */
  label: string;
  /** Higher priority sorts earlier in the output. Defaults to 0. */
  priority?: number;
}

export interface AssignmentResult {
  /** Final deduplicated label set, ordered by descending priority. */
  labels: string[];
  /** Files that matched no rule at all. */
  unmatched: string[];
  /** Per-file breakdown of which labels each file contributed. */
  perFile: Record<string, string[]>;
}

interface LabelInfo {
  label: string;
  priority: number;
  /** Index of the first rule (in declaration order) that produced this label. */
  firstRuleIndex: number;
}

/**
 * Assign labels to a list of changed files using the given rules.
 *
 * A file may match several rules and therefore contribute several labels
 * ("multiple labels per file"). The final set is deduplicated and ordered by
 * descending priority; ties are broken by rule declaration order so the output
 * is deterministic. When a label is produced by more than one rule, the highest
 * priority among those rules wins.
 */
export function assignLabels(
  files: string[],
  rules: LabelRule[],
): AssignmentResult {
  // Highest priority + earliest declaration index seen per label.
  const labelInfo = new Map<string, LabelInfo>();
  const perFile: Record<string, string[]> = {};
  const unmatched: string[] = [];

  for (const file of files) {
    const fileLabels: string[] = [];

    rules.forEach((rule, ruleIndex) => {
      if (!matchGlob(file, rule.pattern)) return;

      const priority = rule.priority ?? 0;
      if (!fileLabels.includes(rule.label)) fileLabels.push(rule.label);

      const existing = labelInfo.get(rule.label);
      if (existing === undefined) {
        labelInfo.set(rule.label, {
          label: rule.label,
          priority,
          firstRuleIndex: ruleIndex,
        });
      } else {
        // Keep the strongest priority and the earliest declaration index.
        existing.priority = Math.max(existing.priority, priority);
        existing.firstRuleIndex = Math.min(
          existing.firstRuleIndex,
          ruleIndex,
        );
      }
    });

    if (fileLabels.length === 0) {
      unmatched.push(file);
    } else {
      perFile[file] = fileLabels;
    }
  }

  const labels = [...labelInfo.values()]
    .sort((a, b) =>
      b.priority - a.priority || a.firstRuleIndex - b.firstRuleIndex,
    )
    .map((info) => info.label);

  return { labels, unmatched, perFile };
}
