// Core semantic versioning functionality

export enum VersionBump {
  MAJOR = "major",
  MINOR = "minor",
  PATCH = "patch",
  NONE = "none",
}

export interface ParsedVersion {
  major: number;
  minor: number;
  patch: number;
}

// Parse a semantic version string (e.g., "1.2.3" or "v1.2.3")
export function parseVersion(versionStr: string): ParsedVersion {
  const cleaned = versionStr.replace(/^v/, "").trim();
  const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)$/);

  if (!match) {
    throw new Error(`Invalid version format: ${versionStr}`);
  }

  return {
    major: parseInt(match[1], 10),
    minor: parseInt(match[2], 10),
    patch: parseInt(match[3], 10),
  };
}

// Format a ParsedVersion back to a string
export function formatVersion(version: ParsedVersion): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

// Bump version based on the type of change
export function bumpVersion(
  currentVersion: string,
  bumpType: VersionBump
): string {
  const parsed = parseVersion(currentVersion);

  if (bumpType === VersionBump.NONE) {
    return formatVersion(parsed);
  }

  if (bumpType === VersionBump.MAJOR) {
    return formatVersion({
      major: parsed.major + 1,
      minor: 0,
      patch: 0,
    });
  }

  if (bumpType === VersionBump.MINOR) {
    return formatVersion({
      major: parsed.major,
      minor: parsed.minor + 1,
      patch: 0,
    });
  }

  // PATCH
  return formatVersion({
    major: parsed.major,
    minor: parsed.minor,
    patch: parsed.patch + 1,
  });
}
