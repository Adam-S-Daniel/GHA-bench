/**
 * Parsing and validation of the raw secrets configuration.
 *
 * The validator is a security tool, so we are strict about input: every
 * malformed field produces a precise, actionable error message rather than a
 * silent default or a cryptic stack trace. Validation is kept separate from the
 * core math (validator.ts) so each concern stays small and testable.
 */
import { parseDate } from "./validator";
import type { SecretConfig } from "./types";

/**
 * Validate one raw secret entry, returning a well-typed {@link SecretConfig}.
 *
 * @param raw   the untrusted JSON value for a single secret
 * @param index 0-based position in the list (used for error context when the
 *              entry has no usable name)
 */
export function validateSecretConfig(raw: unknown, index: number): SecretConfig {
  const positional = `secret #${index + 1}`;

  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error(`${positional}: each secret must be a JSON object.`);
  }
  const obj = raw as Record<string, unknown>;

  // name: required, non-empty
  if (typeof obj.name !== "string" || obj.name.trim() === "") {
    throw new Error(`${positional}: "name" is required and must be a non-empty string.`);
  }
  const name = obj.name;
  const label = `secret "${name}"`;

  // lastRotated: required, strict YYYY-MM-DD; reuse parseDate for the real check
  if (typeof obj.lastRotated !== "string") {
    throw new Error(`${label}: "lastRotated" is required and must be a YYYY-MM-DD string.`);
  }
  try {
    parseDate(obj.lastRotated);
  } catch (err) {
    throw new Error(`${label}: ${(err as Error).message}`);
  }

  // rotationPolicyDays: required, positive integer (a 0/negative cadence is meaningless)
  if (
    typeof obj.rotationPolicyDays !== "number" ||
    !Number.isInteger(obj.rotationPolicyDays) ||
    obj.rotationPolicyDays <= 0
  ) {
    throw new Error(`${label}: "rotationPolicyDays" must be a positive integer (days).`);
  }

  // requiredBy: optional, defaults to []; when present must be string[]
  let requiredBy: string[] = [];
  if (obj.requiredBy !== undefined) {
    if (!Array.isArray(obj.requiredBy) || !obj.requiredBy.every((s) => typeof s === "string")) {
      throw new Error(`${label}: "requiredBy" must be an array of service-name strings.`);
    }
    requiredBy = obj.requiredBy as string[];
  }

  return {
    name,
    lastRotated: obj.lastRotated,
    rotationPolicyDays: obj.rotationPolicyDays,
    requiredBy,
  };
}

/**
 * Parse a top-level config value into a list of validated secrets.
 *
 * Two shapes are accepted for ergonomics:
 *   1. an object `{ "secrets": [ ... ] }` (the canonical form)
 *   2. a bare array `[ ... ]`
 */
export function parseConfig(raw: unknown): SecretConfig[] {
  let list: unknown;
  if (Array.isArray(raw)) {
    list = raw;
  } else if (raw !== null && typeof raw === "object" && "secrets" in raw) {
    list = (raw as Record<string, unknown>).secrets;
  } else {
    throw new Error(
      'Config must be a JSON array of secrets or an object with a "secrets" array.',
    );
  }

  if (!Array.isArray(list)) {
    throw new Error('Config "secrets" must be an array.');
  }

  return list.map((item, index) => validateSecretConfig(item, index));
}

/**
 * Validate the warning window CLI argument: a non-negative integer number of
 * days. Returns the parsed number or throws with a clear message.
 */
export function parseWarningWindow(value: string): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0) {
    throw new Error(`--warning-days must be a non-negative integer, got "${value}".`);
  }
  return n;
}
