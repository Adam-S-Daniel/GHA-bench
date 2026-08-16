import * as fs from "fs";
import * as path from "path";

export interface BumpResult {
  oldVersion: string;
  newVersion: string;
  changeType: "major" | "minor" | "patch" | "none";
  changelog: string;
}

export interface PackageJson {
  version: string;
  [key: string]: unknown;
}

// Parse semantic version from package.json
export function parseVersion(filePath: string): string {
  const content = fs.readFileSync(filePath, "utf-8");
  const pkg = JSON.parse(content) as PackageJson;
  return pkg.version;
}

// Determine the type of version bump based on commit messages
function getChangeType(commits: string[]): "major" | "minor" | "patch" | "none" {
  let hasBreakingChange = false;
  let hasFeature = false;
  let hasFix = false;

  for (const commit of commits) {
    if (
      commit.includes("BREAKING CHANGE") ||
      commit.startsWith("feat!:") ||
      commit.startsWith("feat(") && commit.includes("!:")
    ) {
      hasBreakingChange = true;
    }
    if (commit.startsWith("feat:") || commit.startsWith("feat!:")) {
      hasFeature = true;
    }
    if (commit.startsWith("fix:") || commit.startsWith("fix!:")) {
      hasFix = true;
    }
  }

  if (hasBreakingChange) return "major";
  if (hasFeature) return "minor";
  if (hasFix) return "patch";
  return "none";
}

// Increment version based on change type
function incrementVersion(
  version: string,
  changeType: "major" | "minor" | "patch"
): string {
  const parts = version.split(".");
  const major = parseInt(parts[0], 10);
  const minor = parseInt(parts[1], 10);
  const patch = parseInt(parts[2], 10);

  if (changeType === "major") {
    return `${major + 1}.0.0`;
  } else if (changeType === "minor") {
    return `${major}.${minor + 1}.0`;
  } else {
    return `${major}.${minor}.${patch + 1}`;
  }
}

// Bump version based on conventional commit messages
export function bumpVersion(currentVersion: string, commits: string[]): BumpResult {
  const changeType = getChangeType(commits);
  const newVersion =
    changeType === "none" ? currentVersion : incrementVersion(currentVersion, changeType);

  const changelog = generateChangelog(commits, changeType, newVersion);

  return {
    oldVersion: currentVersion,
    newVersion,
    changeType,
    changelog,
  };
}

// Generate changelog from commits
function generateChangelog(
  commits: string[],
  changeType: string,
  newVersion: string
): string {
  const isBreakingCommit = (c: string) =>
    c.includes("BREAKING CHANGE") || c.startsWith("feat!:") || (c.startsWith("feat(") && c.includes("!:"));
  const isFeature = (c: string) =>
    c.startsWith("feat:") || c.startsWith("feat!:");
  const isFix = (c: string) => c.startsWith("fix:");

  const features = commits.filter(isFeature).filter((c) => !isBreakingCommit(c));
  const fixes = commits.filter(isFix);
  const breaking = commits.filter(isBreakingCommit);

  let changelog = `## [${newVersion}] - ${new Date().toISOString().split("T")[0]}\n`;

  if (breaking.length > 0) {
    changelog += "\n### ⚠️ BREAKING CHANGES\n";
    breaking.forEach((c) => {
      changelog += `- ${extractCommitMessage(c)}\n`;
    });
  }

  if (features.length > 0) {
    changelog += "\n### Features\n";
    features.forEach((c) => {
      changelog += `- ${extractCommitMessage(c)}\n`;
    });
  }

  if (fixes.length > 0) {
    changelog += "\n### Bug Fixes\n";
    fixes.forEach((c) => {
      changelog += `- ${extractCommitMessage(c)}\n`;
    });
  }

  return changelog;
}

// Extract commit message title
function extractCommitMessage(commit: string): string {
  const match = commit.match(/^[^:]+:\s*(.+)/);
  return match ? match[1].split("\n")[0] : commit;
}

// Update version in package.json and optionally CHANGELOG.md
export function updateVersion(
  packageJsonPath: string,
  newVersion: string,
  changelog?: string
): void {
  const dir = path.dirname(packageJsonPath);

  const content = fs.readFileSync(packageJsonPath, "utf-8");
  const pkg = JSON.parse(content) as PackageJson;
  pkg.version = newVersion;
  fs.writeFileSync(packageJsonPath, JSON.stringify(pkg, null, 2) + "\n");

  if (changelog) {
    const changelogPath = path.join(dir, "CHANGELOG.md");
    if (fs.existsSync(changelogPath)) {
      const existing = fs.readFileSync(changelogPath, "utf-8");
      fs.writeFileSync(changelogPath, changelog + "\n" + existing);
    } else {
      fs.writeFileSync(changelogPath, "# Changelog\n\n" + changelog);
    }
  }
}

// Parse git log output into individual commit messages
// Format should be: git log --format=%H%n%s%n%b%n---END---
export function parseGitLog(gitLog: string): string[] {
  if (!gitLog.trim()) return [];

  // Split by commit delimiter
  const commitBlocks = gitLog.split("---END---").filter((block) => block.trim());

  const commits: string[] = [];

  for (const block of commitBlocks) {
    const lines = block.trim().split("\n");
    if (lines.length < 2) continue;

    // Format: hash, subject, then body lines
    const hash = lines[0];
    const subject = lines[1];
    const body = lines.slice(2);

    // Check if this is a conventional commit
    if (/^[a-z]+(?:\(.+\))?!?:/.test(subject)) {
      // Reconstruct the full commit message (subject + body)
      let fullMessage = subject;
      if (body.length > 0) {
        const bodyText = body.join("\n").trim();
        if (bodyText) {
          fullMessage += "\n\n" + bodyText;
        }
      }
      commits.push(fullMessage.trim());
    }
  }

  return commits;
}

// Alternative parser for simple oneline git log format
export function parseGitLogSimple(gitLog: string): string[] {
  if (!gitLog.trim()) return [];

  const lines = gitLog.split("\n").filter((line) => line.trim());
  const commits: string[] = [];

  for (const line of lines) {
    // Remove the commit hash (first word) and keep the message
    const message = line.replace(/^[a-f0-9]+ /, "");
    if (/^[a-z]+(?:\(.+\))?!?:/.test(message)) {
      commits.push(message);
    }
  }

  return commits;
}
