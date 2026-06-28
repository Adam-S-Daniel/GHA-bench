/**
 * Manifest parsing.
 *
 * Turns the raw text of a dependency manifest into a normalized Dependency[].
 * Two formats are supported today: npm's package.json and pip's
 * requirements.txt. Adding another format is a matter of adding a branch here.
 */
import type { Dependency, ManifestType } from "./types.ts";

/**
 * Strip a leading npm-style range specifier from a version string so that
 * "^1.3.0", "~1.3.0", ">=1.3.0", "=1.3.0" and "v1.3.0" all normalize to
 * "1.3.0". This keeps the version we report (and look up) deterministic.
 */
function normalizeVersion(raw: string): string {
  return raw.trim().replace(/^[\^~>=<v\s]+/, "").trim();
}

/** Parse the `dependencies`/`devDependencies` maps of a package.json. */
function parsePackageJson(content: string): Dependency[] {
  let pkg: unknown;
  try {
    pkg = JSON.parse(content);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to parse package.json: ${reason}`);
  }

  if (typeof pkg !== "object" || pkg === null) {
    throw new Error("Failed to parse package.json: expected a JSON object");
  }

  const record = pkg as Record<string, unknown>;
  const deps: Dependency[] = [];

  // Merge runtime and dev dependencies; both are subject to license policy.
  for (const field of ["dependencies", "devDependencies"]) {
    const section = record[field];
    if (section === undefined) continue;
    if (typeof section !== "object" || section === null) {
      throw new Error(`Failed to parse package.json: "${field}" must be an object`);
    }
    for (const [name, version] of Object.entries(section as Record<string, unknown>)) {
      if (typeof version !== "string") {
        throw new Error(
          `Failed to parse package.json: version for "${name}" must be a string`,
        );
      }
      deps.push({ name, version: normalizeVersion(version) });
    }
  }

  return deps;
}

/**
 * Parse a pip requirements.txt. Handles `==`, `>=`, `<=`, `~=`, `>`, `<`
 * specifiers, inline `#` comments, full-line comments, and blank lines.
 */
function parseRequirementsTxt(content: string): Dependency[] {
  const deps: Dependency[] = [];

  for (const line of content.split(/\r?\n/)) {
    // Drop inline comments, then trim surrounding whitespace.
    const stripped = line.replace(/#.*$/, "").trim();
    if (stripped === "") continue;

    // Split on the first version specifier operator.
    const match = stripped.match(/^([A-Za-z0-9._-]+)\s*(==|>=|<=|~=|>|<)\s*(.+)$/);
    if (!match) {
      throw new Error(
        `Failed to parse requirements.txt: cannot understand line "${line.trim()}"`,
      );
    }
    const [, name, , version] = match;
    deps.push({ name, version: version.trim() });
  }

  return deps;
}

/**
 * Parse a dependency manifest of the given type into a normalized list of
 * dependencies. Throws a descriptive error for unsupported types or malformed
 * input so callers can surface a meaningful message.
 */
export function parseManifest(content: string, type: ManifestType): Dependency[] {
  switch (type) {
    case "package.json":
      return parsePackageJson(content);
    case "requirements.txt":
      return parseRequirementsTxt(content);
    default:
      // Exhaustiveness guard: a new ManifestType must add a case above.
      throw new Error(`Unsupported manifest type: ${type as string}`);
  }
}
