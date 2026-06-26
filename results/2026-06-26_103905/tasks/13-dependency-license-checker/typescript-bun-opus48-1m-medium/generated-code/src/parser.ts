// Manifest parsing: turn raw manifest text into a normalized Dependency[].
import type { Dependency, ManifestType } from "./types.ts";

/** Parse a package.json string into a flat list of dependencies. */
function parsePackageJson(content: string): Dependency[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse package.json: ${reason}`);
  }

  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Failed to parse package.json: root is not an object");
  }

  const root = parsed as Record<string, unknown>;
  // Both runtime and dev dependencies are subject to license checks.
  const sections = ["dependencies", "devDependencies"] as const;
  const deps: Dependency[] = [];

  for (const section of sections) {
    const block = root[section];
    if (typeof block !== "object" || block === null) continue;
    for (const [name, version] of Object.entries(block as Record<string, unknown>)) {
      deps.push({ name, version: String(version) });
    }
  }

  return deps;
}

/**
 * Parse a requirements.txt string. Supports the common `==`, `>=`, `<=`,
 * `~=`, `>`, `<` operators and bare (unpinned) package names. Comments
 * (lines starting with `#`) and blank lines are ignored.
 */
function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  // Matches "name <operator> version"; the version group is optional.
  const lineRe = /^([A-Za-z0-9._-]+)\s*(?:==|>=|<=|~=|!=|>|<)?\s*([A-Za-z0-9._*+!-]+)?$/;

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;

    const match = lineRe.exec(line);
    if (!match) {
      throw new Error(`Failed to parse requirements.txt: invalid line "${line}"`);
    }
    const name = match[1]!;
    const version = match[2] ?? "*";
    deps.push({ name, version });
  }

  return deps;
}

/**
 * Parse a dependency manifest of the given type. Throws a descriptive
 * error for malformed input or unsupported manifest types.
 */
export function parseManifest(content: string, type: ManifestType): Dependency[] {
  switch (type) {
    case "package.json":
      return parsePackageJson(content);
    case "requirements.txt":
      return parseRequirementsTxt(content);
    default:
      throw new Error(`Unsupported manifest type: ${type as string}`);
  }
}
