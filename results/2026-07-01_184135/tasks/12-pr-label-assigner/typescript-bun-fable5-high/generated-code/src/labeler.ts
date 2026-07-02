// PR label assigner core.
//
// Semantics:
//  - Every rule maps one glob pattern to one or more labels.
//  - For each changed file, all matching rules are found.
//  - Priority (higher wins, default 0) resolves conflicts *per file*: only
//    the matching rules tied for the highest priority contribute labels for
//    that file. Rules at the same priority are additive.
//  - The final result is the sorted, deduplicated union across all files.
import { matchesGlob } from "./glob";

/** One configurable path-to-label mapping rule. */
export interface LabelRule {
  /** Glob pattern, e.g. "docs/**" or "*.test.*" (no slash → basename match). */
  pattern: string;
  /** Labels to apply when a changed file matches the pattern. */
  labels: string[];
  /** Conflict resolution: higher-priority matches suppress lower ones. Default 0. */
  priority?: number;
}

/** Error type for bad user input (config / file list) — reported without a stack. */
export class InputError extends Error {}

function parseJson(text: string, what: string): unknown {
  try {
    return JSON.parse(text);
  } catch (cause) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    throw new InputError(`${what} is not valid JSON: ${detail}`);
  }
}

/**
 * Parse and validate a rules config document:
 *   { "rules": [ { "pattern": "docs/**", "labels": ["documentation"], "priority": 2 }, ... ] }
 * Every violation names the offending rule index so it can be fixed from a CI log.
 */
export function parseRules(text: string): LabelRule[] {
  const doc = parseJson(text, "Rules config");
  if (
    typeof doc !== "object" ||
    doc === null ||
    !Array.isArray((doc as { rules?: unknown }).rules)
  ) {
    throw new InputError(
      'Rules config must be an object with a top-level "rules" array.',
    );
  }

  return (doc as { rules: unknown[] }).rules.map((raw, i): LabelRule => {
    const where = `rules[${i}]`;
    if (typeof raw !== "object" || raw === null) {
      throw new InputError(`${where} must be an object.`);
    }
    const { pattern, labels, priority } = raw as Record<string, unknown>;

    if (typeof pattern !== "string" || pattern.length === 0) {
      throw new InputError(`${where} is missing a non-empty string "pattern".`);
    }
    if (
      !Array.isArray(labels) ||
      labels.length === 0 ||
      !labels.every((l) => typeof l === "string" && l.length > 0)
    ) {
      throw new InputError(
        `${where} ("${pattern}") needs "labels": a non-empty array of non-empty strings.`,
      );
    }
    if (priority !== undefined && typeof priority !== "number") {
      throw new InputError(
        `${where} ("${pattern}") has a non-numeric "priority": ${JSON.stringify(priority)}.`,
      );
    }

    const rule: LabelRule = { pattern, labels: labels as string[] };
    if (priority !== undefined) rule.priority = priority;
    return rule;
  });
}

/** Parse and validate the changed-file list: a JSON array of path strings. */
export function parseChangedFiles(text: string): string[] {
  const doc = parseJson(text, "Changed-files list");
  if (!Array.isArray(doc)) {
    throw new InputError("Changed-files list must be a JSON array of paths.");
  }
  return doc.map((entry, i) => {
    if (typeof entry !== "string") {
      throw new InputError(
        `Changed-files entry [${i}] must be a string, got ${JSON.stringify(entry)}.`,
      );
    }
    return entry;
  });
}

/** Compute the final label set for a list of changed file paths. */
export function assignLabels(
  changedFiles: string[],
  rules: LabelRule[],
): string[] {
  const labels = new Set<string>();

  for (const file of changedFiles) {
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
