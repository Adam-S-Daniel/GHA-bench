/**
 * Configuration loading and validation.
 *
 * The config file is JSON with a top-level "secrets" array. Every failure
 * mode (missing file, malformed JSON, schema violation) produces a distinct,
 * actionable error message so CI logs tell the operator exactly what to fix.
 */
import { existsSync, readFileSync } from "node:fs";
import type { Secret } from "./types";

/** Validate one raw entry against the Secret shape. */
function validateSecret(raw: unknown, index: number): Secret {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error(`Secret entry #${index + 1} must be an object`);
  }
  const entry = raw as Record<string, unknown>;
  const name = entry.name;
  if (typeof name !== "string" || name.trim() === "") {
    throw new Error(
      `Secret entry #${index + 1}: "name" must be a non-empty string`,
    );
  }
  const label = `Secret "${name}" (entry #${index + 1})`;

  if (typeof entry.lastRotated !== "string") {
    throw new Error(`${label}: "lastRotated" must be a string (YYYY-MM-DD)`);
  }
  if (typeof entry.rotationPolicyDays !== "number") {
    throw new Error(`${label}: "rotationPolicyDays" must be a number`);
  }
  if (
    !Array.isArray(entry.requiredBy) ||
    !entry.requiredBy.every((s) => typeof s === "string")
  ) {
    throw new Error(`${label}: "requiredBy" must be an array of strings`);
  }

  return {
    name,
    lastRotated: entry.lastRotated,
    rotationPolicyDays: entry.rotationPolicyDays,
    requiredBy: entry.requiredBy,
  };
}

/** Read and validate the secrets configuration file. */
export function loadConfig(path: string): Secret[] {
  if (!existsSync(path)) {
    throw new Error(`Configuration file not found: ${path}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Configuration file ${path} is not valid JSON: ${detail}`);
  }

  if (
    typeof parsed !== "object" ||
    parsed === null ||
    !Array.isArray((parsed as Record<string, unknown>).secrets)
  ) {
    throw new Error('Configuration must have a top-level "secrets" array');
  }

  return (parsed as { secrets: unknown[] }).secrets.map(validateSecret);
}
