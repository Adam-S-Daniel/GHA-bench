// Type definitions for semantic versioning
export interface Version {
  major: number;
  minor: number;
  patch: number;
}

export type BumpType = "major" | "minor" | "patch";

// Parse semantic version string (e.g., "1.2.3" or "v1.2.3")
export function parseVersion(versionString: string): Version {
  const cleaned = versionString.startsWith("v")
    ? versionString.slice(1)
    : versionString;
  const parts = cleaned.split(".");

  if (parts.length !== 3) {
    throw new Error(`Invalid version format: ${versionString}`);
  }

  const [major, minor, patch] = parts.map((p) => {
    const num = parseInt(p, 10);
    if (isNaN(num)) {
      throw new Error(`Invalid version format: ${versionString}`);
    }
    return num;
  });

  return { major, minor, patch };
}

// Convert version object back to string
export function versionToString(version: Version): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

// Bump version based on commit type
export function bumpVersion(current: Version, bumpType: BumpType): Version {
  switch (bumpType) {
    case "major":
      return { major: current.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: current.major, minor: current.minor + 1, patch: 0 };
    case "patch":
      return { major: current.major, minor: current.minor, patch: current.patch + 1 };
  }
}
