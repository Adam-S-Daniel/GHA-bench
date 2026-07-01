// Minimal semantic-version (MAJOR.MINOR.PATCH) parsing, formatting, and
// bumping. Deliberately does not support pre-release/build-metadata suffixes
// (e.g. "1.2.3-beta.1+build5") — this tool only needs to compare and bump
// release versions found in a version file or package.json.

export interface Version {
  major: number;
  minor: number;
  patch: number;
}

export type BumpType = "major" | "minor" | "patch" | "none";

const VERSION_PATTERN = /^v?(\d+)\.(\d+)\.(\d+)$/;

/** Parses a "1.2.3" (optionally "v1.2.3") string into a Version. */
export function parseVersion(raw: string): Version {
  const match = VERSION_PATTERN.exec(raw.trim());
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${raw}". Expected format MAJOR.MINOR.PATCH (e.g. "1.2.3").`,
    );
  }
  const [, major, minor, patch] = match;
  return {
    major: Number(major),
    minor: Number(minor),
    patch: Number(patch),
  };
}

/** Formats a Version back into its canonical "MAJOR.MINOR.PATCH" string. */
export function formatVersion(version: Version): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

/** Applies a bump type to a version, following standard semver rules. */
export function bumpVersion(version: Version, bump: BumpType): Version {
  switch (bump) {
    case "major":
      return { major: version.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: version.major, minor: version.minor + 1, patch: 0 };
    case "patch":
      return { ...version, patch: version.patch + 1 };
    case "none":
      return { ...version };
  }
}
