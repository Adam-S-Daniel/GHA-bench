#!/usr/bin/env bun

import {
  parseVersion,
  bumpVersion,
  versionToString,
  parseCommits,
  determineVersionBump,
  readPackageJson,
  writePackageJson,
  generateChangelog,
} from "./version-bumper";

interface Options {
  packageFile: string;
  commits: string[];
  dryRun: boolean;
}

function parseArgs(): Options {
  const args = process.argv.slice(2);
  const packageFile = args[0] || "package.json";
  const dryRun = args.includes("--dry-run");

  // Build commit list from remaining args or from environment
  let commits: string[] = [];
  if (Bun.env.COMMIT_MESSAGES) {
    commits = Bun.env.COMMIT_MESSAGES.split("\n").filter((c) => c.trim());
  } else {
    // Take remaining args after package file and flags as commits
    commits = args
      .filter((a) => a !== "--dry-run" && a !== packageFile)
      .map((a) => a.trim())
      .filter((a) => a);
  }

  return { packageFile, commits, dryRun };
}

async function main(): Promise<void> {
  const options = parseArgs();

  // Validate that we have a package.json to read
  if (!Bun.file(options.packageFile).exists()) {
    console.error(`Error: ${options.packageFile} not found`);
    process.exit(1);
  }

  try {
    // Read current version
    const currentVersion = readPackageJson(options.packageFile);
    console.log(`Current version: ${versionToString(currentVersion)}`);

    // Parse commits
    const parsedCommits = parseCommits(options.commits);

    // Determine version bump
    const bumpType = determineVersionBump(parsedCommits);

    if (bumpType === "none") {
      console.log("No version bump needed");
      process.exit(0);
    }

    // Calculate new version
    const newVersion = bumpVersion(currentVersion, bumpType);
    const newVersionStr = versionToString(newVersion);

    console.log(`Version bump: ${bumpType}`);
    console.log(`New version: ${newVersionStr}`);

    // Generate changelog
    if (parsedCommits.length > 0) {
      const changelog = generateChangelog(parsedCommits);
      if (changelog) {
        console.log("\nChangelog:");
        console.log(changelog);
      }
    }

    // Write new version if not dry-run
    if (!options.dryRun) {
      writePackageJson(options.packageFile, newVersion);
      console.log(`\nUpdated ${options.packageFile}`);
    } else {
      console.log("\n(dry-run: version not written)");
    }

    console.log(newVersionStr);
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error("An unknown error occurred");
    }
    process.exit(1);
  }
}

main();
