/**
 * Loading and validation of the allow/deny license config JSON.
 */
import type { LicenseConfig } from "./types";

function assertStringArray(value: unknown, key: string, path: string): string[] {
  if (
    !Array.isArray(value) ||
    value.some((item) => typeof item !== "string")
  ) {
    throw new Error(
      `Invalid license config at ${path}: "${key}" must be an array of license strings`,
    );
  }
  return value as string[];
}

/** Read and validate a { allow: string[], deny: string[] } config file. */
export async function loadLicenseConfig(path: string): Promise<LicenseConfig> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`License config file not found: ${path}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text());
  } catch (err) {
    throw new Error(
      `Invalid license config at ${path}: not valid JSON (${(err as Error).message})`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`Invalid license config at ${path}: expected a JSON object`);
  }

  const raw = parsed as Record<string, unknown>;
  return {
    allow: assertStringArray(raw.allow, "allow", path),
    deny: assertStringArray(raw.deny, "deny", path),
  };
}
