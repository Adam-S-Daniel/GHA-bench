import type { LicenseConfig } from "./types";

/** True when the value is an array containing only strings. */
function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === "string");
}

/** Load and validate the allow/deny license configuration from JSON. */
export async function loadConfig(configPath: string): Promise<LicenseConfig> {
  const file = Bun.file(configPath);
  if (!(await file.exists())) {
    throw new Error(`Config file not found: ${configPath}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text());
  } catch (err) {
    throw new Error(
      `Invalid JSON in config ${configPath}: ${(err as Error).message}`,
    );
  }
  const config = parsed as Partial<LicenseConfig>;
  if (!isStringArray(config.allow) || !isStringArray(config.deny)) {
    throw new Error(
      `Config must contain "allow" and "deny" arrays of strings: ${configPath}`,
    );
  }
  return { allow: config.allow, deny: config.deny };
}
