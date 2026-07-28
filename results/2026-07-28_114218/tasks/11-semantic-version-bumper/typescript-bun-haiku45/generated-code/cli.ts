#!/usr/bin/env bun
import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import { bumpVersion } from "./version-bumper";

interface CLIOptions {
  versionFile?: string;
  gitRange?: string;
  dry: boolean;
}

// Parse command line arguments
function parseArgs(): CLIOptions {
  const args = process.argv.slice(2);
  const options: CLIOptions = { dry: false };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--version-file":
        options.versionFile = args[++i];
        break;
      case "--git-range":
        options.gitRange = args[++i];
        break;
      case "--dry-run":
        options.dry = true;
        break;
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
    }
  }

  return options;
}

function printHelp(): void {
  console.log(`Semantic Version Bumper

Usage: bun cli.ts [options]

Options:
  --version-file <path>   Path to package.json or VERSION file (default: ./package.json)
  --git-range <range>     Git commit range (e.g., origin/main..HEAD, default: auto-detect)
  --dry-run               Show what would be done without making changes
  --help, -h              Show this help message
`);
}

// Get commits from git log
function getCommitMessages(gitRange?: string): string[] {
  try {
    let range = gitRange;

    // Auto-detect range if not provided
    if (!range) {
      try {
        // Try to find the last git tag
        const lastTag = execSync("git describe --tags --abbrev=0 2>/dev/null", {
          encoding: "utf-8",
        }).trim();
        range = `${lastTag}..HEAD`;
      } catch {
        // If no tags, use all commits
        range = "HEAD~10..HEAD";
      }
    }

    // Get commit messages from git log
    const output = execSync(
      `git log ${range} --format=%B%n---END---`,
      {
        encoding: "utf-8",
      }
    ).trim();

    if (!output) {
      return [];
    }

    // Split by separator and clean up
    const commits = output
      .split("---END---")
      .map((c) => c.trim())
      .filter((c) => c.length > 0);

    return commits;
  } catch (error) {
    console.error("Error reading git log:", (error as Error).message);
    return [];
  }
}

// Resolve version file path (look for package.json or VERSION)
function resolveVersionFile(specified?: string): string {
  if (specified) {
    return specified;
  }

  if (fs.existsSync("package.json")) {
    return "package.json";
  }

  if (fs.existsSync("VERSION")) {
    return "VERSION";
  }

  throw new Error(
    "No version file found. Specify with --version-file or create package.json or VERSION file."
  );
}

// Main entry point
async function main(): Promise<void> {
  try {
    const options = parseArgs();
    const versionFile = resolveVersionFile(options.versionFile);

    if (!fs.existsSync(versionFile)) {
      throw new Error(`Version file not found: ${versionFile}`);
    }

    // Get commits from git
    const commits = getCommitMessages(options.gitRange);

    if (commits.length === 0) {
      console.log("No commits found to process.");
      process.exit(0);
    }

    console.log(`Found ${commits.length} commits to process`);
    console.log(`Version file: ${versionFile}`);
    console.log("");

    if (options.dry) {
      console.log("[DRY RUN] Would bump version with commits:");
      commits.forEach((c) => {
        const firstLine = c.split("\n")[0];
        console.log(`  - ${firstLine}`);
      });
    } else {
      // Execute bump
      const result = bumpVersion(versionFile, commits);
      console.log(`✓ Version bumped: ${result.oldVersion} → ${result.newVersion}`);
      console.log("\nChangelog:");
      console.log(result.changelog);
      console.log(`\n✓ Version file updated: ${versionFile}`);
    }
  } catch (error) {
    console.error("Error:", (error as Error).message);
    process.exit(1);
  }
}

main();
