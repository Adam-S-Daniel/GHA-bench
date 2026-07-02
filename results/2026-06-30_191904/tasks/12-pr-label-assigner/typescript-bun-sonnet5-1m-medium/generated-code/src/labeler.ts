import { matchGlob } from "./glob";
import type { LabelRule } from "./types";

/**
 * Computes the final set of PR labels for a list of changed files given a
 * set of path-to-label rules.
 *
 * - A file may trigger multiple rules; all their labels are included
 *   unless rules share an `exclusiveGroup`.
 * - Rules within the same `exclusiveGroup` are mutually exclusive: only
 *   the highest-`priority` triggered rule in that group contributes its
 *   label (ties broken by rule order, earlier wins).
 */
export function assignLabels(files: string[], rules: LabelRule[]): string[] {
  validateRules(rules);

  const triggeredRules = rules.filter((rule) =>
    files.some((file) => matchGlob(rule.pattern, file)),
  );

  const ungroupedLabels = triggeredRules
    .filter((rule) => rule.exclusiveGroup === undefined)
    .map((rule) => rule.label);

  const groupWinners = resolveExclusiveGroups(triggeredRules);

  return dedupe([...ungroupedLabels, ...groupWinners]);
}

function resolveExclusiveGroups(triggeredRules: LabelRule[]): string[] {
  const groups = new Map<string, LabelRule>();
  for (const rule of triggeredRules) {
    if (rule.exclusiveGroup === undefined) continue;
    const currentWinner = groups.get(rule.exclusiveGroup);
    const rulePriority = rule.priority ?? 0;
    if (!currentWinner || rulePriority > (currentWinner.priority ?? 0)) {
      groups.set(rule.exclusiveGroup, rule);
    }
  }
  return [...groups.values()].map((rule) => rule.label);
}

function dedupe(labels: string[]): string[] {
  return [...new Set(labels)];
}

function validateRules(rules: LabelRule[]): void {
  rules.forEach((rule, index) => {
    if (!rule.pattern || typeof rule.pattern !== "string") {
      throw new Error(`Rule at index ${index} is missing a valid "pattern" string.`);
    }
    if (!rule.label || typeof rule.label !== "string") {
      throw new Error(`Rule at index ${index} is missing a valid "label" string.`);
    }
  });
}
