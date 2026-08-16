// Main entry point for semantic version bumper

import { parseVersion, bumpVersion, VersionBump } from "./semver";
import { parseCommitMessage, determineVersionBump } from "./commits";
import { readVersionFromFile, writeVersionToFile, FileType } from "./files";
import { getCommitsSinceTag } from "./git";
import { generateChangelogEntry } from "./changelog";
import { existsSync } from "fs";

interface Options {
  versionFile?: string;
  previousTag?: string;
  changelogFile?: string;
  dryRun?: boolean;
}

async function main() {
  const options: Options = {
    versionFile: "package.json",
    previousTag: "v1.0.0",
    changelogFile: "CHANGELOG.md",
    dryRun: false,
  };

  // Parse command line arguments
  const args = process.argv.slice(2);
  let i = 0;
  while (i < args.length) {
    switch (args[i]) {
      case "--version-file":
        options.versionFile = args[++i];
        break;
      case "--previous-tag":
        options.previousTag = args[++i];
        break;
      case "--changelog-file":
        options.changelogFile = args[++i];
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      default:
        console.error(`Unknown option: ${args[i]}`);
        process.exit(1);
    }
    i++;
  }

  try {
    // Validate that version file exists
    if (!existsSync(options.versionFile!)) {
      throw new Error(`Version file not found: ${options.versionFile}`);
    }

    // Read current version
    const fileType = options.versionFile!.endsWith("package.json")
      ? FileType.PACKAGE_JSON
      : FileType.VERSION;
    const currentVersion = readVersionFromFile(options.versionFile!, fileType);

    console.log(`Current version: ${currentVersion}`);

    // Get commits since previous tag
    const cwd = process.cwd();
    const commits = getCommitsSinceTag(cwd, options.previousTag!);

    console.log(`Found ${commits.length} commits since ${options.previousTag}`);

    // Determine version bump type
    const bumpType = determineVersionBump(commits);
    console.log(`Version bump type: ${bumpType}`);

    // Calculate new version
    const newVersion = bumpVersion(currentVersion, bumpType);
    console.log(`New version: ${newVersion}`);

    if (bumpType === VersionBump.NONE && commits.length > 0) {
      console.log(
        "No version bump needed (only docs/chore commits or no commits)"
      );
    }

    // Generate changelog entry if there are meaningful commits
    if (commits.length > 0 && bumpType !== VersionBump.NONE) {
      const changelogEntry = generateChangelogEntry(newVersion, commits);

      if (!options.dryRun) {
        // Write new version to file
        writeVersionToFile(options.versionFile!, newVersion, fileType);
        console.log(`✓ Updated ${options.versionFile} to ${newVersion}`);

        // Append changelog entry (if changelog file is specified)
        if (options.changelogFile) {
          const fs = await import("fs");
          const existing = fs.existsSync(options.changelogFile)
            ? fs.readFileSync(options.changelogFile, "utf-8")
            : "";
          fs.writeFileSync(
            options.changelogFile,
            changelogEntry + "\n" + existing
          );
          console.log(`✓ Updated ${options.changelogFile}`);
        }
      } else {
        console.log("\n[DRY RUN] Would update files:");
        console.log(`[DRY RUN] ${options.versionFile}: ${currentVersion} → ${newVersion}`);
        if (options.changelogFile) {
          console.log(`[DRY RUN] ${options.changelogFile}: prepend entry for ${newVersion}`);
        }
      }

      // Output the new version for CI/CD to capture
      console.log(`\n::VERSION::${newVersion}`);
    } else {
      // Even if no bump, output current version
      console.log(`\n::VERSION::${currentVersion}`);
    }
  } catch (error) {
    console.error(
      "Error:",
      error instanceof Error ? error.message : String(error)
    );
    process.exit(1);
  }
}

main();
