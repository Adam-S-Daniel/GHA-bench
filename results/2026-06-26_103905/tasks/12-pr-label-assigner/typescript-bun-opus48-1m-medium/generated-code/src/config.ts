// Config and input parsing with graceful, meaningful error messages.
import type { LabelRule } from "./label-assigner.ts";

export interface Config {
  rules: LabelRule[];
}

/**
 * Parse and validate a JSON config string into a {@link Config}.
 * Throws Error with an actionable message on any malformed input.
 */
export function parseConfig(raw: string): Config {
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Invalid config JSON: ${reason}`);
  }

  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new Error('Config must be a JSON object containing a "rules" array.');
  }

  const rulesValue = (data as Record<string, unknown>).rules;
  if (!Array.isArray(rulesValue)) {
    throw new Error('Config must contain a "rules" array.');
  }

  const rules: LabelRule[] = rulesValue.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error(`Config rule at index ${index} must be an object.`);
    }
    const rule = entry as Record<string, unknown>;
    if (typeof rule.pattern !== "string" || rule.pattern.length === 0) {
      throw new Error(
        `Config rule at index ${index} is missing a non-empty "pattern" string.`,
      );
    }
    if (typeof rule.label !== "string" || rule.label.length === 0) {
      throw new Error(
        `Config rule at index ${index} is missing a non-empty "label" string.`,
      );
    }
    if (rule.priority !== undefined && typeof rule.priority !== "number") {
      throw new Error(
        `Config rule at index ${index} has a non-numeric "priority".`,
      );
    }
    return {
      pattern: rule.pattern,
      label: rule.label,
      ...(rule.priority !== undefined ? { priority: rule.priority } : {}),
    };
  });

  return { rules };
}

/**
 * Parse a newline-delimited list of changed files (e.g. a mocked PR diff).
 * Trims whitespace and drops blank lines.
 */
export function parseFileList(raw: string): string[] {
  return raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}
