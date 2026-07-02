import { basename } from "node:path";
import type { Dependency } from "./types";

/**
 * Manifest parsing. Two formats are supported:
 *   - npm package.json (dependencies + devDependencies)
 *   - pip requirements.txt (pinned `==`, ranged `>=`/`<=`/`~=`, bare names)
 * Dispatch is by file name suffix so callers can point at any path.
 */

/** Parse an npm package.json manifest body. */
function parsePackageJson(content: string): Dependency[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    throw new Error(
      `Invalid JSON in package.json manifest: ${(err as Error).message}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Invalid JSON in package.json manifest: expected an object");
  }
  const manifest = parsed as Record<string, unknown>;
  const deps: Dependency[] = [];
  for (const section of ["dependencies", "devDependencies"]) {
    const block = manifest[section];
    if (block === undefined) continue;
    if (typeof block !== "object" || block === null) {
      throw new Error(`Invalid package.json manifest: "${section}" must be an object`);
    }
    for (const [name, version] of Object.entries(block as Record<string, unknown>)) {
      if (typeof version !== "string") {
        throw new Error(
          `Invalid package.json manifest: version of "${name}" must be a string`,
        );
      }
      deps.push({ name, version });
    }
  }
  return deps;
}

/** Parse a pip requirements.txt manifest body. */
function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) continue;
    // name==1.2.3 -> exact version; name>=1.2 -> keep the range as-is;
    // a bare name has no constraint, which we record as "*".
    const pinned = line.match(/^([A-Za-z0-9._-]+)==(.+)$/);
    if (pinned) {
      deps.push({ name: pinned[1]!, version: pinned[2]!.trim() });
      continue;
    }
    const ranged = line.match(/^([A-Za-z0-9._-]+)((?:>=|<=|~=|>|<|!=).+)$/);
    if (ranged) {
      deps.push({ name: ranged[1]!, version: ranged[2]!.trim() });
      continue;
    }
    if (/^[A-Za-z0-9._-]+$/.test(line)) {
      deps.push({ name: line, version: "*" });
      continue;
    }
    throw new Error(`Invalid requirements.txt line: "${line}"`);
  }
  return deps;
}

/**
 * Parse manifest content, dispatching on the manifest file name.
 * Throws on unsupported manifest types with a meaningful message.
 */
export function parseManifest(content: string, filename: string): Dependency[] {
  const base = basename(filename);
  if (base.endsWith("package.json")) return parsePackageJson(content);
  if (base.endsWith("requirements.txt")) return parseRequirementsTxt(content);
  throw new Error(
    `Unsupported manifest type: ${base} (supported: package.json, requirements.txt)`,
  );
}

/** Read a manifest from disk and parse it. */
export async function parseManifestFile(path: string): Promise<Dependency[]> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Manifest file not found: ${path}`);
  }
  return parseManifest(await file.text(), path);
}
