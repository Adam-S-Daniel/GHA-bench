// Loads and validates the secrets configuration (mock data describing the
// secrets we're tracking). Every failure mode produces a specific,
// human-readable message so a CI log tells you exactly what to fix.
import { parseIsoDate } from "./dateUtils.ts";
import type { Secret, SecretsConfig } from "./types.ts";

const DEFAULT_WARNING_WINDOW_DAYS: number = 14;

/** Thrown for any structurally invalid secrets config. */
export class SecretConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SecretConfigError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validateSecret(raw: unknown, index: number): Secret {
  const prefix: string = `secrets[${index}]`;
  if (!isRecord(raw)) {
    throw new SecretConfigError(`${prefix} must be an object`);
  }

  const { name, lastRotated, rotationPolicyDays, requiredBy } = raw;

  if (typeof name !== "string" || name.trim() === "") {
    throw new SecretConfigError(`${prefix}.name must be a non-empty string`);
  }

  if (typeof lastRotated !== "string") {
    throw new SecretConfigError(`${prefix}.lastRotated must be a string in YYYY-MM-DD format`);
  }
  try {
    parseIsoDate(lastRotated);
  } catch (cause) {
    const reason: string = cause instanceof Error ? cause.message : String(cause);
    throw new SecretConfigError(`${prefix}.lastRotated is invalid: ${reason}`);
  }

  if (
    typeof rotationPolicyDays !== "number" ||
    !Number.isFinite(rotationPolicyDays) ||
    rotationPolicyDays <= 0 ||
    !Number.isInteger(rotationPolicyDays)
  ) {
    throw new SecretConfigError(
      `${prefix}.rotationPolicyDays must be a positive integer, got ${JSON.stringify(rotationPolicyDays)}`,
    );
  }

  if (!Array.isArray(requiredBy) || !requiredBy.every((item) => typeof item === "string")) {
    throw new SecretConfigError(`${prefix}.requiredBy must be an array of strings`);
  }

  return {
    name,
    lastRotated,
    rotationPolicyDays,
    requiredBy: [...requiredBy],
  };
}

/** Validates an already-parsed JSON value and returns a typed SecretsConfig. */
export function parseConfig(raw: unknown): SecretsConfig {
  if (!isRecord(raw)) {
    throw new SecretConfigError("Config must be a JSON object");
  }

  const { secrets, warningWindowDays } = raw;

  if (!Array.isArray(secrets)) {
    throw new SecretConfigError('Config field "secrets" must be an array');
  }

  let resolvedWarningWindowDays: number = DEFAULT_WARNING_WINDOW_DAYS;
  if (warningWindowDays !== undefined) {
    if (
      typeof warningWindowDays !== "number" ||
      !Number.isFinite(warningWindowDays) ||
      warningWindowDays < 0
    ) {
      throw new SecretConfigError(
        `Config field "warningWindowDays" must be a non-negative number, got ${JSON.stringify(warningWindowDays)}`,
      );
    }
    resolvedWarningWindowDays = warningWindowDays;
  }

  return {
    warningWindowDays: resolvedWarningWindowDays,
    secrets: secrets.map((secret, index) => validateSecret(secret, index)),
  };
}

/** Reads a config file from disk, parses its JSON, and validates it. */
export async function loadConfigFile(path: string): Promise<SecretsConfig> {
  let text: string;
  try {
    text = await Bun.file(path).text();
  } catch (cause) {
    const reason: string = cause instanceof Error ? cause.message : String(cause);
    throw new SecretConfigError(`Could not read config file "${path}": ${reason}`);
  }

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (cause) {
    const reason: string = cause instanceof Error ? cause.message : String(cause);
    throw new SecretConfigError(`Invalid JSON in config file "${path}": ${reason}`);
  }

  return parseConfig(raw);
}
