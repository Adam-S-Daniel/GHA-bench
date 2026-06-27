// Config parsing + validation. Produces a typed SecretConfig from a JSON string,
// throwing descriptive errors so misconfigured inputs fail loudly and clearly.
import { parseIsoDate, type Secret, type SecretConfig } from "./validator.ts";

/** Assert `value` is a plain object (and narrow its type for TypeScript). */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Validate a single raw secret entry, returning a typed Secret or throwing. */
function validateSecret(raw: unknown, index: number): Secret {
  const where = `secrets[${index}]`;
  if (!isRecord(raw)) {
    throw new Error(`${where} must be an object`);
  }

  if (typeof raw.name !== "string" || raw.name.length === 0) {
    throw new Error(`${where} is missing a non-empty string "name"`);
  }
  const name = raw.name;

  if (typeof raw.lastRotated !== "string") {
    throw new Error(`${where} (${name}) is missing string "lastRotated"`);
  }
  // Reuse the strict date parser so malformed dates are caught at load time.
  parseIsoDate(raw.lastRotated, `${where} (${name}) lastRotated`);

  if (typeof raw.rotationPolicyDays !== "number" || !Number.isFinite(raw.rotationPolicyDays)) {
    throw new Error(`${where} (${name}) is missing numeric "rotationPolicyDays"`);
  }
  if (raw.rotationPolicyDays <= 0) {
    throw new Error(`${where} (${name}) rotationPolicyDays must be a positive number`);
  }

  if (
    !Array.isArray(raw.requiredBy) ||
    !raw.requiredBy.every((s): s is string => typeof s === "string")
  ) {
    throw new Error(`${where} (${name}) "requiredBy" must be an array of strings`);
  }

  return {
    name,
    lastRotated: raw.lastRotated,
    rotationPolicyDays: raw.rotationPolicyDays,
    requiredBy: raw.requiredBy,
  };
}

/** Parse and validate a raw JSON config string into a typed SecretConfig. */
export function parseConfig(rawJson: string): SecretConfig {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to parse config JSON: ${message}`);
  }

  if (!isRecord(parsed) || !Array.isArray(parsed.secrets)) {
    throw new Error('Config must have a "secrets" array at the top level');
  }

  const secrets = parsed.secrets.map((raw, index) => validateSecret(raw, index));
  return { secrets };
}
