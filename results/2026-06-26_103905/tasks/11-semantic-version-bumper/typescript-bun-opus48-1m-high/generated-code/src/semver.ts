// src/semver.ts
// Pure, dependency-free helpers for working with semantic versions.
// Kept deliberately small and side-effect free so it is trivially testable.

/** A parsed semantic version. We only model the MAJOR.MINOR.PATCH core. */
export interface SemanticVersion {
  major: number;
  minor: number;
  patch: number;
}

/**
 * The kind of bump to apply. `"none"` means "no release-worthy commits", in
 * which case the version is left untouched. The ordering of the union mirrors
 * its precedence: major > minor > patch > none.
 */
export type BumpType = "major" | "minor" | "patch" | "none";

// Matches an optional leading "v", then three dot-separated integer groups.
// Anchored so partial strings like "1.2" are rejected.
const SEMVER_RE = /^v?(\d+)\.(\d+)\.(\d+)$/;

/**
 * Parse a semantic version string into its components.
 * Tolerates a leading `v` and surrounding whitespace; throws otherwise.
 */
export function parseVersion(input: string): SemanticVersion {
  const trimmed = input.trim();
  const match = SEMVER_RE.exec(trimmed);
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${input}". Expected MAJOR.MINOR.PATCH (e.g. 1.2.3).`,
    );
  }
  // match[1..3] are guaranteed to be digit strings by the regex.
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

/** Render a SemanticVersion back to its canonical "MAJOR.MINOR.PATCH" form. */
export function formatVersion(version: SemanticVersion): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

/**
 * Produce a NEW version object by applying `bump` to `version`.
 * Follows semver rules: a higher-level bump resets all lower components to 0.
 * Never mutates the input.
 */
export function bumpVersion(version: SemanticVersion, bump: BumpType): SemanticVersion {
  switch (bump) {
    case "major":
      return { major: version.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: version.major, minor: version.minor + 1, patch: 0 };
    case "patch":
      return { major: version.major, minor: version.minor, patch: version.patch + 1 };
    case "none":
      return { ...version };
  }
}

/**
 * Compare two versions. Returns a negative number if `a < b`, positive if
 * `a > b`, and 0 if they are equal — the standard Array.sort comparator shape.
 */
export function compareVersions(a: SemanticVersion, b: SemanticVersion): number {
  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  return a.patch - b.patch;
}
