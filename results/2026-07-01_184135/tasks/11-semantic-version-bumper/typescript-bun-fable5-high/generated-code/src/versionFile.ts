/**
 * GREEN phase (cycle 4): version-file I/O.
 *
 * Approach: the file's basename decides the strategy — "package.json" is
 * treated as JSON (only its "version" field is rewritten, everything else
 * preserved), anything else is a plain one-line version file. All failure
 * modes throw errors that name the file and the problem.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { formatVersion, parseVersion, type SemVer } from "./semver";

function isPackageJson(path: string): boolean {
  return basename(path) === "package.json";
}

function readRaw(path: string): string {
  if (!existsSync(path)) {
    throw new Error(`Version file not found: "${path}"`);
  }
  return readFileSync(path, "utf8");
}

function parsePackageJson(path: string, raw: string): Record<string, unknown> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(
      `"${path}" is not valid JSON: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error(`"${path}" is not a JSON object`);
  }
  return parsed as Record<string, unknown>;
}

/** Read the current version from a VERSION file or a package.json. */
export function readVersionFile(path: string): SemVer {
  const raw = readRaw(path);
  if (!isPackageJson(path)) return parseVersion(raw);

  const pkg = parsePackageJson(path, raw);
  if (typeof pkg.version !== "string") {
    throw new Error(`"${path}" has no "version" field to bump`);
  }
  return parseVersion(pkg.version);
}

/** Write the new version back, preserving package.json structure. */
export function writeVersionFile(path: string, version: SemVer): void {
  if (!isPackageJson(path)) {
    writeFileSync(path, `${formatVersion(version)}\n`);
    return;
  }
  const pkg = parsePackageJson(path, readRaw(path));
  pkg.version = formatVersion(version);
  writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`);
}
