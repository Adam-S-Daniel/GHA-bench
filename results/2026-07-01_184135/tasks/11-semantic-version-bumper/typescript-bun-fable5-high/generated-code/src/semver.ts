/**
 * GREEN phase (cycle 1): minimal semantic-version parsing/bumping.
 *
 * Approach: a SemVer is modelled as a plain typed object so bump logic is
 * pure arithmetic — no string munging beyond the initial parse.
 */

/** A parsed semantic version (we only need the core triple for bumping). */
export interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

/** The kind of bump derived from conventional commits. */
export type BumpType = "major" | "minor" | "patch" | "none";

const SEMVER_RE = /^v?(\d+)\.(\d+)\.(\d+)$/;

/**
 * Parse "1.2.3" (optionally "v1.2.3", surrounding whitespace allowed) into a
 * SemVer. Throws with the offending input on anything else.
 */
export function parseVersion(raw: string): SemVer {
  const trimmed = raw.trim();
  const match = SEMVER_RE.exec(trimmed);
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${trimmed}" (expected MAJOR.MINOR.PATCH, e.g. "1.2.3")`,
    );
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

/** Render a SemVer back to its canonical "x.y.z" string form. */
export function formatVersion(v: SemVer): string {
  return `${v.major}.${v.minor}.${v.patch}`;
}

/**
 * Apply a bump. SemVer rules: a major bump zeroes minor+patch, a minor bump
 * zeroes patch, "none" is the identity (no releasable commits).
 */
export function bumpVersion(v: SemVer, bump: BumpType): SemVer {
  switch (bump) {
    case "major":
      return { major: v.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: v.major, minor: v.minor + 1, patch: 0 };
    case "patch":
      return { major: v.major, minor: v.minor, patch: v.patch + 1 };
    case "none":
      return { ...v };
  }
}
