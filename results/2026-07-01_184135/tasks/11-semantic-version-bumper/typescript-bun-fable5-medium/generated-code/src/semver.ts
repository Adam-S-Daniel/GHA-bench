// Minimal semantic-version handling: parse "MAJOR.MINOR.PATCH", format it
// back, and bump one of the three parts per semver rules.

/** The three numeric components of a semantic version. */
export interface Semver {
  major: number;
  minor: number;
  patch: number;
}

/** Which component of the version to increment. */
export type BumpType = "major" | "minor" | "patch";

const SEMVER_RE = /^v?(\d+)\.(\d+)\.(\d+)$/;

/**
 * Parse a "1.2.3" (optionally "v1.2.3") string. Throws with a clear message
 * on anything that is not a plain three-part semver.
 */
export function parseSemver(input: string): Semver {
  const match = SEMVER_RE.exec(input.trim());
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${input}" (expected MAJOR.MINOR.PATCH, e.g. 1.2.3)`,
    );
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

export function formatSemver(v: Semver): string {
  return `${v.major}.${v.minor}.${v.patch}`;
}

/**
 * Apply a semver bump: major resets minor+patch, minor resets patch,
 * patch increments in place.
 */
export function bumpVersion(current: string, type: BumpType): string {
  const v = parseSemver(current);
  switch (type) {
    case "major":
      return formatSemver({ major: v.major + 1, minor: 0, patch: 0 });
    case "minor":
      return formatSemver({ major: v.major, minor: v.minor + 1, patch: 0 });
    case "patch":
      return formatSemver({ ...v, patch: v.patch + 1 });
  }
}
