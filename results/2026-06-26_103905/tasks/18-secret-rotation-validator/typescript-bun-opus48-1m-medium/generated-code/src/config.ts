// Parsing and validation of the secret configuration input.
// Accepts either a bare array of secrets or an object with a `secrets` key.
import type { Secret } from "./types";

/** Validate a single raw object and coerce it into a Secret. */
function validateSecret(raw: unknown, index: number): Secret {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error(`Secret at index ${index} must be an object`);
  }
  const obj = raw as Record<string, unknown>;

  if (typeof obj.name !== "string" || obj.name.trim() === "") {
    throw new Error(`Secret at index ${index} is missing a valid "name"`);
  }
  if (typeof obj.lastRotated !== "string") {
    throw new Error(`Secret "${obj.name}" is missing a valid "lastRotated" date string`);
  }
  if (typeof obj.rotationPolicyDays !== "number" || !Number.isFinite(obj.rotationPolicyDays)) {
    throw new Error(
      `Secret "${obj.name}" has an invalid "rotationPolicyDays" (must be a number)`,
    );
  }

  // requiredBy is optional; default to [] and validate element types.
  let requiredBy: string[] = [];
  if (obj.requiredBy !== undefined) {
    if (
      !Array.isArray(obj.requiredBy) ||
      !obj.requiredBy.every((v) => typeof v === "string")
    ) {
      throw new Error(`Secret "${obj.name}" has an invalid "requiredBy" (must be string[])`);
    }
    requiredBy = obj.requiredBy as string[];
  }

  return {
    name: obj.name,
    lastRotated: obj.lastRotated,
    rotationPolicyDays: obj.rotationPolicyDays,
    requiredBy,
  };
}

/**
 * Parse raw JSON text into a validated array of secrets.
 * @throws with a clear message on malformed JSON or invalid structure.
 */
export function parseConfig(text: string): Secret[] {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse configuration JSON: ${reason}`);
  }

  let list: unknown;
  if (Array.isArray(data)) {
    list = data;
  } else if (
    typeof data === "object" &&
    data !== null &&
    Array.isArray((data as Record<string, unknown>).secrets)
  ) {
    list = (data as Record<string, unknown>).secrets;
  } else {
    throw new Error(
      'Configuration must be an array of secrets or an object with a "secrets" array',
    );
  }

  return (list as unknown[]).map(validateSecret);
}
