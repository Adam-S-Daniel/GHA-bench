import { existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import type { Dependency } from "./types";

/**
 * Parses a dependency manifest file and returns the flat list of
 * declared dependencies. Supports npm's package.json (dependencies +
 * devDependencies) and Python's requirements.txt.
 *
 * The manifest format is chosen by filename, not extension, since
 * requirements.txt has no extension of its own to key off.
 */
export function parseManifest(filePath: string): Dependency[] {
  if (!existsSync(filePath)) {
    throw new Error(`Manifest file not found: ${filePath}`);
  }

  const contents = readFileSync(filePath, "utf-8");
  const name = basename(filePath);

  if (name === "package.json") {
    return parsePackageJson(filePath, contents);
  }
  if (name === "requirements.txt") {
    return parseRequirementsTxt(contents);
  }

  throw new Error(
    `Unsupported manifest type for "${filePath}". Expected package.json or requirements.txt.`,
  );
}

function parsePackageJson(filePath: string, contents: string): Dependency[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(contents);
  } catch (cause) {
    throw new Error(`Invalid JSON in manifest file: ${filePath}`, { cause });
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`Invalid JSON in manifest file: ${filePath}`);
  }

  const pkg = parsed as Record<string, unknown>;
  const deps: Dependency[] = [];

  for (const section of ["dependencies", "devDependencies"] as const) {
    const sectionValue = pkg[section];
    if (!sectionValue || typeof sectionValue !== "object") continue;

    for (const [depName, rawVersion] of Object.entries(
      sectionValue as Record<string, unknown>,
    )) {
      deps.push({
        name: depName,
        version: cleanSemverRange(String(rawVersion)),
      });
    }
  }

  return deps;
}

/** Strips leading range operators (^ ~ >= <= > < =) so we're left with a bare version. */
function cleanSemverRange(rawVersion: string): string {
  const trimmed = rawVersion.trim();
  if (trimmed === "*" || trimmed === "") return "*";
  return trimmed.replace(/^[\^~]|^(>=|<=|==|>|<|=)/, "").trim();
}

const REQUIREMENT_LINE = /^([A-Za-z0-9._-]+)\s*(==|>=|<=|~=|!=|>|<)?\s*(.*)$/;

function parseRequirementsTxt(contents: string): Dependency[] {
  const deps: Dependency[] = [];

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#") || line.startsWith("-")) continue;

    const match = REQUIREMENT_LINE.exec(line);
    if (!match) continue;

    const [, depName, , versionPart] = match;
    const version = versionPart && versionPart.trim() !== "" ? versionPart.trim() : "*";
    deps.push({ name: depName as string, version });
  }

  return deps;
}
