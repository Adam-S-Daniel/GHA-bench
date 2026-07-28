import { promises as fs } from "fs";

export enum CommitType {
  BREAKING = "breaking",
  FEAT = "feat",
  FIX = "fix",
  OTHER = "other",
}

export interface Commit {
  message: string;
  type: CommitType;
}

export interface ParsedVersion {
  major: number;
  minor: number;
  patch: number;
}

// Parse semantic version from package.json
export async function parseVersion(filePath: string): Promise<string> {
  const content = await fs.readFile(filePath, "utf-8");
  const parsed = JSON.parse(content);
  return parsed.version;
}

// Parse version string into components
function parseVersionString(version: string): ParsedVersion {
  const parts = version.split(".");
  return {
    major: parseInt(parts[0], 10),
    minor: parseInt(parts[1], 10),
    patch: parseInt(parts[2], 10),
  };
}

// Detect the type of version bump based on commits
export function detectBumpType(commits: Commit[]): "major" | "minor" | "patch" {
  const hasBreaking = commits.some((c) => c.type === CommitType.BREAKING);
  const hasFeature = commits.some((c) => c.type === CommitType.FEAT);
  const hasFix = commits.some((c) => c.type === CommitType.FIX);

  if (hasBreaking) return "major";
  if (hasFeature) return "minor";
  if (hasFix) return "patch";

  return "patch";
}

// Bump version based on type
export function bumpVersion(
  version: string,
  bumpType: "major" | "minor" | "patch"
): string {
  const parsed = parseVersionString(version);

  if (bumpType === "major") {
    return `${parsed.major + 1}.0.0`;
  } else if (bumpType === "minor") {
    return `${parsed.major}.${parsed.minor + 1}.0`;
  } else {
    return `${parsed.major}.${parsed.minor}.${parsed.patch + 1}`;
  }
}

// Generate changelog from commits
export function generateChangelog(version: string, commits: Commit[]): string {
  let changelog = `## [${version}]\n\n`;

  const features = commits.filter((c) => c.type === CommitType.FEAT);
  const fixes = commits.filter((c) => c.type === CommitType.FIX);
  const breaking = commits.filter((c) => c.type === CommitType.BREAKING);

  if (breaking.length > 0) {
    changelog += "### Breaking Changes\n";
    breaking.forEach((c) => {
      changelog += `- ${extractCommitMessage(c.message)}\n`;
    });
    changelog += "\n";
  }

  if (features.length > 0) {
    changelog += "### Features\n";
    features.forEach((c) => {
      changelog += `- ${extractCommitMessage(c.message)}\n`;
    });
    changelog += "\n";
  }

  if (fixes.length > 0) {
    changelog += "### Fixes\n";
    fixes.forEach((c) => {
      changelog += `- ${extractCommitMessage(c.message)}\n`;
    });
    changelog += "\n";
  }

  return changelog;
}

// Extract message from conventional commit
function extractCommitMessage(message: string): string {
  // Remove conventional commit prefix (e.g., "feat:", "fix:", "feat!:")
  return message.replace(/^(feat|fix|docs|style|refactor|perf|test)(\!)?:\s*/, "");
}

// Update version in package.json file
export async function updateVersionInFile(
  filePath: string,
  newVersion: string
): Promise<void> {
  const content = await fs.readFile(filePath, "utf-8");
  const parsed = JSON.parse(content);
  parsed.version = newVersion;
  await fs.writeFile(filePath, JSON.stringify(parsed, null, 2) + "\n");
}

// Main orchestration function
export async function bumpSemanticVersion(
  packageJsonPath: string,
  commits: Commit[]
): Promise<{
  oldVersion: string;
  newVersion: string;
  changelog: string;
}> {
  const oldVersion = await parseVersion(packageJsonPath);
  const bumpType = detectBumpType(commits);
  const newVersion = bumpVersion(oldVersion, bumpType);
  const changelog = generateChangelog(newVersion, commits);

  await updateVersionInFile(packageJsonPath, newVersion);

  return {
    oldVersion,
    newVersion,
    changelog,
  };
}
