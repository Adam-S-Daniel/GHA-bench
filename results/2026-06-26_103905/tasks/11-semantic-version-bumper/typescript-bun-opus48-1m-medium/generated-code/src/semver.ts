// Core semantic-version primitives: parse, format, and bump.
// Kept dependency-free so it is trivially unit-testable.

/** A parsed semantic version (we only model major.minor.patch). */
export interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

/** The kind of release bump, ordered by precedence (major > minor > patch). */
export type BumpType = "major" | "minor" | "patch";

// Strict-ish semver core matcher. We allow an optional leading "v".
const VERSION_RE = /^v?(\d+)\.(\d+)\.(\d+)$/;

/**
 * Parse a dotted semantic version string into a {@link SemVer}.
 * Throws with a clear message when the input is not a valid version.
 */
export function parseVersion(input: string): SemVer {
  const match = VERSION_RE.exec(input.trim());
  if (!match) {
    throw new Error(`Invalid semantic version: "${input}"`);
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

/** Render a {@link SemVer} back into a "major.minor.patch" string. */
export function formatVersion(v: SemVer): string {
  return `${v.major}.${v.minor}.${v.patch}`;
}

/**
 * Produce a new {@link SemVer} bumped by the given {@link BumpType}.
 * Following semver rules, a higher-precedence bump resets the lower fields.
 */
export function bumpVersion(current: SemVer, bump: BumpType): SemVer {
  switch (bump) {
    case "major":
      return { major: current.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: current.major, minor: current.minor + 1, patch: 0 };
    case "patch":
      return { major: current.major, minor: current.minor, patch: current.patch + 1 };
    default:
      // Exhaustiveness guard — should be unreachable with correct typing.
      throw new Error(`Unknown bump type: ${bump as string}`);
  }
}
