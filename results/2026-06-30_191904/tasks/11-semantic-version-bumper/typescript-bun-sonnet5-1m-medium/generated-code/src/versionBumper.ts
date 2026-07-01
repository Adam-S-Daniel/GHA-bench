// Core logic for the semantic version bumper.
// Pure functions here have no filesystem/CLI concerns so they are easy to unit test.

export interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

export type BumpType = "major" | "minor" | "patch" | "none";

const SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)$/;

/** Parses a "MAJOR.MINOR.PATCH" string into its numeric components. */
export function parseVersion(version: string): SemVer {
  const match = SEMVER_PATTERN.exec(version.trim());
  if (!match) {
    throw new Error(
      `Invalid semantic version string: "${version}". Expected format MAJOR.MINOR.PATCH (e.g. "1.2.3").`,
    );
  }
  const [, major, minor, patch] = match;
  return { major: Number(major), minor: Number(minor), patch: Number(patch) };
}

/** Formats a SemVer back into a "MAJOR.MINOR.PATCH" string. */
export function formatVersion(version: SemVer): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

const BREAKING_FOOTER_PATTERN = /^BREAKING[ -]CHANGE:/i;
const CONVENTIONAL_COMMIT_PATTERN = /^(\w+)(\([^)]*\))?(!)?:\s*(.+)$/;

/**
 * Determines the required version bump from a list of conventional commit
 * messages, applying the standard precedence: major > minor > patch > none.
 */
export function determineBumpType(commits: string[]): BumpType {
  let bump: BumpType = "none";

  for (const commit of commits) {
    const trimmed = commit.trim();
    if (!trimmed) continue;

    if (BREAKING_FOOTER_PATTERN.test(trimmed)) {
      return "major";
    }

    const match = CONVENTIONAL_COMMIT_PATTERN.exec(trimmed);
    if (!match) continue;

    const [, type, , breakingMarker] = match;
    if (breakingMarker === "!") {
      return "major";
    }

    if (type === "feat" && bump !== "minor") {
      bump = "minor";
    } else if (type === "fix" && bump === "none") {
      bump = "patch";
    }
  }

  return bump;
}

/** Applies a bump type to a version string, returning the new version. */
export function bumpVersion(version: string, bump: BumpType): string {
  const parsed = parseVersion(version);

  switch (bump) {
    case "major":
      return formatVersion({ major: parsed.major + 1, minor: 0, patch: 0 });
    case "minor":
      return formatVersion({
        major: parsed.major,
        minor: parsed.minor + 1,
        patch: 0,
      });
    case "patch":
      return formatVersion({
        major: parsed.major,
        minor: parsed.minor,
        patch: parsed.patch + 1,
      });
    case "none":
      return formatVersion(parsed);
  }
}
