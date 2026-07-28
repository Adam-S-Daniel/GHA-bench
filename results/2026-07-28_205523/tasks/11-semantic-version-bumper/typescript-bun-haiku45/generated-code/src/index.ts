#!/usr/bin/env bun

import { parseVersion, bumpVersion, versionToString } from "./version";
import { determineBumpType, parseCommit } from "./commits";
import { generateChangelogEntry } from "./changelog";
import { readPackageVersion, writePackageVersion } from "./files";
import { parseGitLog } from "./git";
import { execSync } from "child_process";
import { readFileSync, writeFileSync, appendFileSync } from "fs";
import { existsSync } from "fs";

interface Options {
  packageJsonPath: string;
  changelogPath: string;
  lastTag?: string;
  dryRun: boolean;
}

// Get commits since the last tag
function getCommitsSince(lastTag: string): Array<{ hash: string; message: string; body: string }> {
  try {
    // Get all commits since tag in format: hash%n%s%n%b%n---END---
    const format = "%H%n%s%n%b%n---END---";
    const logCmd = lastTag ? `git log ${lastTag}..HEAD --pretty=format:'${format}'` : `git log --pretty=format:'${format}'`;

    const output = execSync(logCmd, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] });
    return parseGitLog(output);
  } catch (error) {
    console.warn("Warning: Failed to get git commits, using empty list");
    return [];
  }
}

// Main function
async function main() {
  const args = process.argv.slice(2);

  const options: Options = {
    packageJsonPath: "package.json",
    changelogPath: "CHANGELOG.md",
    lastTag: process.env.LAST_TAG,
    dryRun: args.includes("--dry-run"),
  };

  // Parse command line arguments
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--package-json" && i + 1 < args.length) {
      options.packageJsonPath = args[i + 1];
      i++;
    } else if (args[i] === "--changelog" && i + 1 < args.length) {
      options.changelogPath = args[i + 1];
      i++;
    } else if (args[i] === "--last-tag" && i + 1 < args.length) {
      options.lastTag = args[i + 1];
      i++;
    }
  }

  try {
    // Read current version
    const currentVersionStr = readPackageVersion(options.packageJsonPath);
    const currentVersion = parseVersion(currentVersionStr);

    console.log(`Current version: ${versionToString(currentVersion)}`);

    // Get commits since last tag
    const commits = getCommitsSince(options.lastTag || "HEAD~0");
    console.log(`Found ${commits.length} commits since ${options.lastTag || "last commit"}`);

    if (commits.length === 0) {
      console.log("No commits found, no version bump needed");
      console.log(currentVersionStr);
      return;
    }

    // Determine bump type based on commits
    const bumpType = determineBumpType(commits);
    console.log(`Determined bump type: ${bumpType}`);

    // Calculate new version
    const newVersion = bumpVersion(currentVersion, bumpType);
    const newVersionStr = versionToString(newVersion);

    console.log(`New version: ${newVersionStr}`);

    // Generate changelog entry
    const changelogEntry = generateChangelogEntry(newVersionStr, commits);

    if (!options.dryRun) {
      // Update package.json
      writePackageVersion(options.packageJsonPath, newVersionStr);
      console.log(`Updated ${options.packageJsonPath}`);

      // Write changelog entry
      if (existsSync(options.changelogPath)) {
        const existingChangelog = readFileSync(options.changelogPath, "utf-8");
        writeFileSync(options.changelogPath, changelogEntry + "\n" + existingChangelog);
      } else {
        writeFileSync(options.changelogPath, changelogEntry);
      }
      console.log(`Updated ${options.changelogPath}`);
    }

    // Output the new version (for CI/CD pipelines)
    console.log("");
    console.log("VERSION=" + newVersionStr);
    process.stdout.write(newVersionStr);
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error("Error: Unknown error occurred");
    }
    process.exit(1);
  }
}

main();
