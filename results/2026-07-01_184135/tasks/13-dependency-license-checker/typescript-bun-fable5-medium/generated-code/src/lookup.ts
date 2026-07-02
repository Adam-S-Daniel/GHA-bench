import type { LicenseLookup } from "./types";

/**
 * Production license lookup: a local JSON database mapping package name to
 * SPDX license id. Kept behind the LicenseLookup function type so tests can
 * swap in an in-memory mock without touching the filesystem.
 */
export async function loadLicenseLookup(dbPath: string): Promise<LicenseLookup> {
  const file = Bun.file(dbPath);
  if (!(await file.exists())) {
    throw new Error(`License database file not found: ${dbPath}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text());
  } catch (err) {
    throw new Error(
      `Invalid JSON in license database ${dbPath}: ${(err as Error).message}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error(
      `License database ${dbPath} must be a JSON object of name -> license`,
    );
  }
  const db = parsed as Record<string, unknown>;
  return (dep) => {
    const license = db[dep.name];
    return typeof license === "string" ? license : undefined;
  };
}
