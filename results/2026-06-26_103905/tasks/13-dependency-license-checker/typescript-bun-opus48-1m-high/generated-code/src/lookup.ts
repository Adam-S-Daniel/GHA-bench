/**
 * License lookup.
 *
 * The rest of the system depends only on the `LicenseLookup` function type
 * (see types.ts), so the source of license data is pluggable. Here we provide
 * a database-backed lookup: a plain JSON map from `name@version` or bare `name`
 * to a license id. This doubles as the "mock" used in tests AND as the offline
 * data source for CI (no network calls, fully deterministic).
 */
import type { Dependency, LicenseLookup } from "./types.ts";

export type { Dependency, LicenseLookup } from "./types.ts";

/** A static license database: key is `name@version` or bare `name`. */
export type LicenseDatabase = Record<string, string>;

/**
 * Build a LicenseLookup backed by a static database. Resolution order:
 *   1. exact `name@version` key (most specific)
 *   2. bare `name` key (applies to any version)
 *   3. null  -> unknown
 */
export function createDatabaseLookup(db: LicenseDatabase): LicenseLookup {
  return (dep: Dependency): string | null => {
    const versioned = `${dep.name}@${dep.version}`;
    if (Object.prototype.hasOwnProperty.call(db, versioned)) {
      return db[versioned];
    }
    if (Object.prototype.hasOwnProperty.call(db, dep.name)) {
      return db[dep.name];
    }
    return null;
  };
}

/** Parse + validate a license database from a JSON string. */
export function loadDatabase(json: string): LicenseDatabase {
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse license database: ${reason}`);
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new Error("Failed to parse license database: expected a JSON object");
  }
  const db: LicenseDatabase = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value !== "string") {
      throw new Error(
        `Invalid license database: license for "${key}" must be a string`,
      );
    }
    db[key] = value;
  }
  return db;
}
