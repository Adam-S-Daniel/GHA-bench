import type { Dependency } from "./types";

/** Parses a package.json's dependencies + devDependencies into a flat Dependency list. */
export function parsePackageJson(content: string): Dependency[] {
  let data: unknown;
  try {
    data = JSON.parse(content);
  } catch (err) {
    throw new Error(`Failed to parse package.json: invalid JSON (${(err as Error).message})`);
  }

  const pkg = data as { dependencies?: Record<string, string>; devDependencies?: Record<string, string> };
  const deps: Dependency[] = [];
  for (const section of [pkg.dependencies, pkg.devDependencies]) {
    if (!section) continue;
    for (const [name, version] of Object.entries(section)) {
      deps.push({ name, version });
    }
  }
  return deps;
}

/** Parses a requirements.txt (pip) file into a flat Dependency list. Supports `name==version` pins. */
export function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const match = line.match(/^([A-Za-z0-9_.-]+)\s*==\s*([A-Za-z0-9_.-]+)$/);
    if (match) {
      deps.push({ name: match[1], version: match[2] });
    } else {
      deps.push({ name: line, version: "unknown" });
    }
  }
  return deps;
}
