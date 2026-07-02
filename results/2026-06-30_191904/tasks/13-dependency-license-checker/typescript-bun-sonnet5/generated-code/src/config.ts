import { existsSync, readFileSync } from "node:fs";
import type { LicenseConfig } from "./types";

/** Loads and validates the allow/deny license policy from a JSON file. */
export function loadLicenseConfig(filePath: string): LicenseConfig {
  if (!existsSync(filePath)) {
    throw new Error(`License policy file not found: ${filePath}`);
  }

  const contents = readFileSync(filePath, "utf-8");
  let parsed: unknown;
  try {
    parsed = JSON.parse(contents);
  } catch (cause) {
    throw new Error(`Invalid JSON in license policy file: ${filePath}`, { cause });
  }

  if (
    typeof parsed !== "object" ||
    parsed === null ||
    !Array.isArray((parsed as Record<string, unknown>).allowlist) ||
    !Array.isArray((parsed as Record<string, unknown>).denylist)
  ) {
    throw new Error(
      `License policy file must have "allowlist" and "denylist" arrays: ${filePath}`,
    );
  }

  const record = parsed as { allowlist: unknown[]; denylist: unknown[] };
  return {
    allowlist: record.allowlist.map(String),
    denylist: record.denylist.map(String),
  };
}
