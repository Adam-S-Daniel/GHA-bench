/**
 * License lookup implementations.
 *
 * A real deployment would query a package registry; to keep the tool
 * deterministic and testable, the default implementation reads a local JSON
 * "license database" mapping package name -> SPDX license. Tests and CI
 * supply that file as a fixture, which is how the lookup is mocked.
 */
import type { LicenseLookup } from "./types";

/** Load a JSON license database from disk and wrap it as a LicenseLookup. */
export async function loadFileLicenseLookup(path: string): Promise<LicenseLookup> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Cannot read license database: file not found at ${path}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text());
  } catch (err) {
    throw new Error(
      `Cannot read license database at ${path}: not valid JSON (${(err as Error).message})`,
    );
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error(`Invalid license database at ${path}: expected a JSON object`);
  }

  const db: Record<string, string> = {};
  for (const [name, license] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof license !== "string") {
      throw new Error(
        `Invalid license database at ${path}: value for "${name}" must be a string`,
      );
    }
    db[name] = license;
  }

  return {
    getLicense: async (name: string): Promise<string | null> => db[name] ?? null,
  };
}
