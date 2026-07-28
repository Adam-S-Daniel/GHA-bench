// Version type represents semantic versioning: major.minor.patch
interface Version {
  major: number;
  minor: number;
  patch: number;
}

// Parsed conventional commit
interface Commit {
  type: "fix" | "feat" | "chore" | "docs" | "style" | "refactor" | "test" | "other";
  description: string;
  isBreaking: boolean;
}

// Parse a version string (e.g., "1.2.3" or "v1.2.3") into a Version object
export function parseVersion(versionString: string): Version {
  const cleaned = versionString.replace(/^v/, "");
  const parts = cleaned.split(".");

  if (parts.length !== 3) {
    throw new Error(`Invalid version format: ${versionString}. Expected major.minor.patch`);
  }

  const major = parseInt(parts[0], 10);
  const minor = parseInt(parts[1], 10);
  const patch = parseInt(parts[2], 10);

  if (isNaN(major) || isNaN(minor) || isNaN(patch)) {
    throw new Error(`Invalid version format: ${versionString}. Expected numeric components`);
  }

  return { major, minor, patch };
}

// Bump version based on commit type (major, minor, or patch)
export function bumpVersion(version: Version, bumpType: "major" | "minor" | "patch"): Version {
  switch (bumpType) {
    case "major":
      return { major: version.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: version.major, minor: version.minor + 1, patch: 0 };
    case "patch":
      return { major: version.major, minor: version.minor, patch: version.patch + 1 };
  }
}

// Format a Version object back to a version string
export function versionToString(version: Version): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

// Parse commit messages using conventional commit format
export function parseCommits(messages: string[]): Commit[] {
  return messages.map((message) => {
    const lines = message.split("\n");
    const firstLine = lines[0];

    // Parse type and description from "type(scope): description" or "type!: description"
    const typeMatch = firstLine.match(/^(\w+)(!)?(?:\([^)]+\))?\s*:\s*(.+)$/);
    if (!typeMatch) {
      return {
        type: "other",
        description: firstLine,
        isBreaking: false,
      };
    }

    const typeStr = typeMatch[1];
    const hasExclamation = typeMatch[2] === "!";
    const description = typeMatch[3];

    // Determine commit type
    let type: Commit["type"] = "other";
    if (typeStr === "fix") type = "fix";
    else if (typeStr === "feat") type = "feat";
    else if (typeStr === "chore") type = "chore";
    else if (typeStr === "docs") type = "docs";
    else if (typeStr === "style") type = "style";
    else if (typeStr === "refactor") type = "refactor";
    else if (typeStr === "test") type = "test";

    // Check for breaking change indicator
    const isBreaking = hasExclamation || message.includes("BREAKING CHANGE");

    return { type, description, isBreaking };
  });
}

// Determine what version bump is needed based on commits
export function determineVersionBump(
  commits: Commit[]
): "major" | "minor" | "patch" | "none" {
  if (commits.length === 0) return "none";

  // Breaking changes require major version bump
  if (commits.some((c) => c.isBreaking)) return "major";

  // Features require minor version bump
  if (commits.some((c) => c.type === "feat")) return "minor";

  // Only fixes/chores/docs require patch version bump
  if (commits.some((c) => c.type === "fix")) return "patch";

  return "none";
}

// Read version from package.json file
export function readPackageJson(filePath: string): Version {
  const fs = require("fs");
  const content = fs.readFileSync(filePath, "utf-8");
  const packageJson = JSON.parse(content);
  return parseVersion(packageJson.version);
}

// Write version to package.json file
export function writePackageJson(filePath: string, version: Version): void {
  const fs = require("fs");
  const content = fs.readFileSync(filePath, "utf-8");
  const packageJson = JSON.parse(content);
  packageJson.version = versionToString(version);
  fs.writeFileSync(filePath, JSON.stringify(packageJson, null, 2));
}

// Generate changelog markdown from commits
export function generateChangelog(commits: Commit[]): string {
  if (commits.length === 0) return "";

  const features = commits.filter((c) => c.type === "feat");
  const fixes = commits.filter((c) => c.type === "fix");
  const breaking = commits.filter((c) => c.isBreaking);

  let changelog = "";

  if (breaking.length > 0) {
    changelog += "### Breaking Changes\n";
    breaking.forEach((c) => {
      changelog += `- ${c.description}\n`;
    });
    changelog += "\n";
  }

  if (features.length > 0) {
    changelog += "### Features\n";
    features.forEach((c) => {
      changelog += `- ${c.description}\n`;
    });
    changelog += "\n";
  }

  if (fixes.length > 0) {
    changelog += "### Bug Fixes\n";
    fixes.forEach((c) => {
      changelog += `- ${c.description}\n`;
    });
    changelog += "\n";
  }

  return changelog.trim();
}

// Stub function to demonstrate getting commit log
// In real usage, this would call git log
export function getCommitLog(_since?: string): string[] {
  return [];
}
