// Parses dependency manifests (package.json, requirements.txt) into a
// normalized list of { name, version } dependencies.

import type { Dependency } from "./types";

/** Strips leading range/pin operators (^, ~, >=, <=, ==, >, <, =) from a version string. */
function cleanVersion(raw: string): string {
  return raw.replace(/^[\^~=<>! ]+/, "").trim();
}

export function parsePackageJson(content: string): Dependency[] {
  let parsed: { dependencies?: Record<string, string>; devDependencies?: Record<string, string> };
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    throw new Error(`Invalid package.json: could not parse JSON (${(err as Error).message})`);
  }

  const deps: Dependency[] = [];
  for (const section of [parsed.dependencies, parsed.devDependencies]) {
    if (!section) continue;
    for (const [name, version] of Object.entries(section)) {
      deps.push({ name, version: cleanVersion(version) });
    }
  }
  return deps;
}

export function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const match = line.match(/^([A-Za-z0-9_.\-\[\]]+)\s*(==|>=|<=|~=)\s*([A-Za-z0-9_.\-]+)/);
    if (match) {
      deps.push({ name: match[1], version: match[3] });
    } else {
      deps.push({ name: line, version: "unknown" });
    }
  }
  return deps;
}

/** Dispatches to the correct parser based on the manifest file's extension/name. */
export function parseManifest(fileName: string, content: string): Dependency[] {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".json")) {
    return parsePackageJson(content);
  }
  if (lower.endsWith(".txt")) {
    return parseRequirementsTxt(content);
  }
  throw new Error(`Unsupported manifest type: ${fileName}`);
}
