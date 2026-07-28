import * as fs from "fs";
import * as path from "path";

interface SemanticVersion {
  major: number;
  minor: number;
  patch: number;
}

interface ParsedCommit {
  type: string;
  scope?: string;
  message: string;
  breaking: boolean;
}

interface BumpResult {
  oldVersion: string;
  newVersion: string;
  changelog: string;
}

// Parse semantic version string (e.g., "1.2.3" or "v1.2.3")
export function parseVersion(versionStr: string): SemanticVersion {
  const cleaned = versionStr.replace(/^v/, "").split("-")[0];
  const parts = cleaned.split(".");

  if (parts.length !== 3) {
    throw new Error(`Invalid semantic version format: ${versionStr}`);
  }

  const major = parseInt(parts[0], 10);
  const minor = parseInt(parts[1], 10);
  const patch = parseInt(parts[2], 10);

  if (isNaN(major) || isNaN(minor) || isNaN(patch)) {
    throw new Error(`Invalid semantic version format: ${versionStr}`);
  }

  return { major, minor, patch };
}

// Parse conventional commit messages
export function parseConventionalCommits(
  commitMessages: string[]
): ParsedCommit[] {
  return commitMessages.map((msg) => {
    const lines = msg.split("\n");
    const firstLine = lines[0];

    // Check for breaking change indicator (!)
    const breakingMatch = firstLine.match(/^(\w+)(\(.+?\))?!:/);
    const isBreakingFromExclamation = !!breakingMatch;

    // Check for BREAKING CHANGE footer
    const isBreakingFromFooter = lines.some((line) =>
      line.startsWith("BREAKING CHANGE:")
    );

    const breaking = isBreakingFromExclamation || isBreakingFromFooter;

    // Parse type and scope
    const typeMatch = firstLine.match(/^(\w+)(?:\(([^)]+)\))?(!)?:/);
    if (!typeMatch) {
      return { type: "other", message: firstLine, breaking: false };
    }

    const type = typeMatch[1];
    const scope = typeMatch[2];
    const messageStart = firstLine.indexOf(":") + 1;
    const message = firstLine.substring(messageStart).trim();

    return { type, scope, message, breaking };
  });
}

// Determine next version based on commits
export function determineNextVersion(
  current: SemanticVersion,
  commitMessages: string[]
): SemanticVersion {
  if (commitMessages.length === 0) {
    return current;
  }

  const commits = parseConventionalCommits(commitMessages);

  let hasBreaking = false;
  let hasFeature = false;
  let hasFix = false;

  for (const commit of commits) {
    if (commit.breaking) {
      hasBreaking = true;
    } else if (commit.type === "feat") {
      hasFeature = true;
    } else if (commit.type === "fix") {
      hasFix = true;
    }
  }

  if (hasBreaking) {
    return { major: current.major + 1, minor: 0, patch: 0 };
  }

  if (hasFeature) {
    return { major: current.major, minor: current.minor + 1, patch: 0 };
  }

  if (hasFix) {
    return { major: current.major, minor: current.minor, patch: current.patch + 1 };
  }

  return current;
}

// Format version to string
function formatVersion(version: SemanticVersion): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

// Update version in file (package.json or VERSION file)
export function updateVersionFile(filePath: string, newVersion: string): void {
  if (filePath.endsWith("package.json")) {
    const content = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    content.version = newVersion;
    fs.writeFileSync(filePath, JSON.stringify(content, null, 2) + "\n");
  } else {
    fs.writeFileSync(filePath, newVersion + "\n");
  }
}

// Generate changelog entry
export function generateChangelog(
  newVersion: string,
  commitMessages: string[]
): string {
  const date = new Date().toISOString().split("T")[0];
  const commits = parseConventionalCommits(commitMessages);

  const feats = commits.filter((c) => c.type === "feat");
  const fixes = commits.filter((c) => c.type === "fix");
  const others = commits.filter((c) => c.type !== "feat" && c.type !== "fix");

  let changelog = `\n## [${newVersion}] - ${date}\n`;

  if (feats.length > 0) {
    changelog += "\n### Features\n";
    for (const feat of feats) {
      changelog += `- ${feat.message}\n`;
    }
  }

  if (fixes.length > 0) {
    changelog += "\n### Bug Fixes\n";
    for (const fix of fixes) {
      changelog += `- ${fix.message}\n`;
    }
  }

  if (others.length > 0) {
    changelog += "\n### Other\n";
    for (const other of others) {
      if (other.type !== "other") {
        changelog += `- **${other.type}**: ${other.message}\n`;
      } else {
        changelog += `- ${other.message}\n`;
      }
    }
  }

  return changelog;
}

// Main function: bump version and generate changelog
export function bumpVersion(
  versionFilePath: string,
  commitMessages: string[]
): BumpResult {
  // Read current version
  let currentVersionStr: string;
  if (versionFilePath.endsWith("package.json")) {
    const pkg = JSON.parse(fs.readFileSync(versionFilePath, "utf-8"));
    currentVersionStr = pkg.version;
  } else {
    currentVersionStr = fs.readFileSync(versionFilePath, "utf-8").trim();
  }

  const currentVersion = parseVersion(currentVersionStr);
  const nextVersion = determineNextVersion(currentVersion, commitMessages);
  const nextVersionStr = formatVersion(nextVersion);

  // Update version file
  updateVersionFile(versionFilePath, nextVersionStr);

  // Generate changelog
  const changelog = generateChangelog(nextVersionStr, commitMessages);

  return {
    oldVersion: formatVersion(currentVersion),
    newVersion: nextVersionStr,
    changelog,
  };
}
