/**
 * Manifest parsing: turn ecosystem-specific dependency manifests into a
 * normalized, sorted Dependency[] list.
 */
import type { Dependency } from "./types";

/** Strip common range specifiers (^, ~, >=, ==, etc.) down to a bare version. */
function normalizeVersion(raw: string): string {
  return raw.trim().replace(/^[\^~=<>!]+/, "").trim();
}

/** Parse a package.json string into dependencies + devDependencies. */
function parsePackageJson(content: string): Dependency[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    throw new Error(
      `Failed to parse package.json: file is not valid JSON (${(err as Error).message})`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Failed to parse package.json: expected a JSON object at the top level");
  }

  const manifest = parsed as Record<string, unknown>;
  const deps: Dependency[] = [];
  for (const section of ["dependencies", "devDependencies"]) {
    const block = manifest[section];
    if (block === undefined) continue;
    if (typeof block !== "object" || block === null) {
      throw new Error(`Failed to parse package.json: "${section}" must be an object`);
    }
    for (const [name, version] of Object.entries(block as Record<string, unknown>)) {
      if (typeof version !== "string") {
        throw new Error(
          `Failed to parse package.json: version for "${name}" must be a string`,
        );
      }
      deps.push({ name, version: normalizeVersion(version) });
    }
  }
  return deps.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Parse a pip requirements.txt. Handles pinned (==), ranged (>=, ~=) and
 * bare requirements; strips comments and blank lines.
 */
function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    // Drop inline comments, then whitespace.
    const line = lines[i].replace(/#.*$/, "").trim();
    if (line === "") continue;

    // name[extras] <specifier> version — capture name and first version.
    const match = line.match(/^([A-Za-z0-9._-]+)(?:\[[^\]]*\])?\s*(?:[=<>~!]+\s*([^,;\s]+))?/);
    if (!match || !match[1]) {
      throw new Error(
        `Failed to parse requirements.txt: cannot understand line ${i + 1}: "${lines[i]}"`,
      );
    }
    deps.push({ name: match[1], version: match[2] ?? "*" });
  }
  return deps.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Parse a manifest by filename hint. Supported formats:
 *  - package.json (npm)
 *  - requirements.txt (pip)
 */
export function parseManifest(content: string, filename: string): Dependency[] {
  if (filename.endsWith("package.json")) return parsePackageJson(content);
  if (filename.endsWith("requirements.txt")) return parseRequirementsTxt(content);
  throw new Error(
    `Unsupported manifest type: "${filename}" (supported: package.json, requirements.txt)`,
  );
}
