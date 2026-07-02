/**
 * Config loading and validation.
 *
 * Approach: validate every field of every entry up front and fail with a
 * message that names the offending entry (by index or name), so a bad config
 * is diagnosable straight from a CI log.
 */
import type { SecretConfig } from "./types";
import { parseIsoDate } from "./validator";

/** Error type for anything wrong with the secrets configuration. */
export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

/** Parse and validate the raw JSON text of a secrets config file. */
export function parseConfig(jsonText: string): SecretConfig[] {
  let data: unknown;
  try {
    data = JSON.parse(jsonText);
  } catch (err) {
    throw new ConfigError(
      `config is not valid JSON: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  if (!Array.isArray(data)) {
    throw new ConfigError("config top level must be an array of secrets");
  }

  const seen = new Set<string>();
  return data.map((entry, index) => {
    const secret = validateEntry(entry, index);
    if (seen.has(secret.name)) {
      throw new ConfigError(`duplicate secret name "${secret.name}"`);
    }
    seen.add(secret.name);
    return secret;
  });
}

function validateEntry(entry: unknown, index: number): SecretConfig {
  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new ConfigError(`secret at index ${index}: must be an object`);
  }
  const record = entry as Record<string, unknown>;

  const name = record["name"];
  if (typeof name !== "string" || name.trim() === "") {
    throw new ConfigError(
      `secret at index ${index}: "name" must be a non-empty string`,
    );
  }
  // From here on we can reference the secret by name, which reads better.
  const where = `secret "${name}"`;

  const lastRotated = record["lastRotated"];
  if (typeof lastRotated !== "string") {
    throw new ConfigError(`${where}: "lastRotated" must be a YYYY-MM-DD string`);
  }
  try {
    parseIsoDate(lastRotated);
  } catch (err) {
    throw new ConfigError(
      `${where}: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  const rotationPolicyDays = record["rotationPolicyDays"];
  if (
    typeof rotationPolicyDays !== "number" ||
    !Number.isInteger(rotationPolicyDays) ||
    rotationPolicyDays <= 0
  ) {
    throw new ConfigError(
      `${where}: "rotationPolicyDays" must be a positive integer (got ${JSON.stringify(rotationPolicyDays)})`,
    );
  }

  const requiredBy = record["requiredBy"];
  if (
    !Array.isArray(requiredBy) ||
    requiredBy.some((s) => typeof s !== "string" || s.trim() === "")
  ) {
    throw new ConfigError(
      `${where}: "requiredBy" must be an array of service names`,
    );
  }

  return { name, lastRotated, rotationPolicyDays, requiredBy };
}
