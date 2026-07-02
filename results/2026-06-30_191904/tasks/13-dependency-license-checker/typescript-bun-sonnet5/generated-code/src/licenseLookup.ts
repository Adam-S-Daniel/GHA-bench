import { existsSync, readFileSync } from "node:fs";
import type { Dependency, LicenseLookup } from "./types";

/**
 * Builds a LicenseLookup backed by a plain name/version -> license map,
 * standing in for a real registry call (npm, PyPI, ...). Used both by unit
 * tests and by the CLI, which loads its map from a fixture/config file so
 * report output stays deterministic in CI.
 *
 * Keys may be "name@version" for an exact match, or just "name" as a
 * fallback that applies to any version of that package.
 */
export function createMockLicenseLookup(
  licenseMap: Readonly<Record<string, string>>,
): LicenseLookup {
  return async (dependency: Dependency): Promise<string | null> => {
    const exactKey = `${dependency.name}@${dependency.version}`;
    if (exactKey in licenseMap) return licenseMap[exactKey] as string;
    if (dependency.name in licenseMap) return licenseMap[dependency.name] as string;
    return null;
  };
}

/** Loads a mock license map from a JSON file on disk. */
export function loadLicenseMapFromFile(filePath: string): Record<string, string> {
  if (!existsSync(filePath)) {
    throw new Error(`License data file not found: ${filePath}`);
  }

  const contents = readFileSync(filePath, "utf-8");
  let parsed: unknown;
  try {
    parsed = JSON.parse(contents);
  } catch (cause) {
    throw new Error(`Invalid JSON in license data file: ${filePath}`, { cause });
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`Invalid JSON in license data file: ${filePath}`);
  }

  return parsed as Record<string, string>;
}
