// Orchestration + CLI entrypoint for the semantic version bumper.
//
// Usage: bun run src/index.ts <commitLogPath> <packageJsonPath> [changelogPath]
//
// Reads a mock commit log, determines the required semver bump from
// conventional commit messages, updates the version field in the given
// package.json, prepends a changelog entry, and prints the new version.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { determineBumpType, bumpVersion, type BumpType } from "./versionBumper";
import { parseCommitLog, generateChangelogEntry } from "./changelog";

export interface RunVersionBumpOptions {
  packageJsonPath: string;
  commitLogPath: string;
  changelogPath: string;
  /** ISO date (YYYY-MM-DD) used in the changelog heading. Defaults to today. */
  date?: string;
}

export interface RunVersionBumpResult {
  previousVersion: string;
  newVersion: string;
  bumpType: BumpType;
  commits: string[];
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Reads, bumps, and writes the version file + changelog. Returns a summary of what happened. */
export function runVersionBump(
  options: RunVersionBumpOptions,
): RunVersionBumpResult {
  const { packageJsonPath, commitLogPath, changelogPath } = options;
  const date = options.date ?? todayIso();

  if (!existsSync(commitLogPath)) {
    throw new Error(
      `Commit log file not found: "${commitLogPath}". Provide a valid path to a mock commit log.`,
    );
  }
  if (!existsSync(packageJsonPath)) {
    throw new Error(
      `Version file not found: "${packageJsonPath}". Provide a valid path to a package.json.`,
    );
  }

  const rawCommitLog = readFileSync(commitLogPath, "utf-8");
  const commits = parseCommitLog(rawCommitLog);

  const rawPackageJson = readFileSync(packageJsonPath, "utf-8");
  let pkg: Record<string, unknown>;
  try {
    pkg = JSON.parse(rawPackageJson);
  } catch (err) {
    throw new Error(
      `Failed to parse "${packageJsonPath}" as JSON: ${(err as Error).message}`,
    );
  }
  if (typeof pkg.version !== "string") {
    throw new Error(
      `"${packageJsonPath}" is missing a string "version" field.`,
    );
  }
  const previousVersion = pkg.version;

  const bumpType = determineBumpType(commits);
  const newVersion = bumpVersion(previousVersion, bumpType);

  pkg.version = newVersion;
  writeFileSync(packageJsonPath, JSON.stringify(pkg, null, 2) + "\n");

  const entry = generateChangelogEntry({ version: newVersion, date, commits });
  const existingChangelog = existsSync(changelogPath)
    ? readFileSync(changelogPath, "utf-8")
    : "# Changelog\n\n";

  const insertionPoint = existingChangelog.indexOf("\n\n") + 2;
  const updatedChangelog =
    existingChangelog.slice(0, insertionPoint) +
    entry +
    "\n" +
    existingChangelog.slice(insertionPoint);
  writeFileSync(changelogPath, updatedChangelog);

  return { previousVersion, newVersion, bumpType, commits };
}

// CLI entrypoint: only runs when this file is executed directly (not on import,
// e.g. by the test suite).
if (import.meta.main) {
  const [commitLogPath, packageJsonPath, changelogPath] = process.argv.slice(2);

  if (!commitLogPath || !packageJsonPath) {
    console.error(
      "Usage: bun run src/index.ts <commitLogPath> <packageJsonPath> [changelogPath]",
    );
    process.exit(1);
  }

  try {
    const result = runVersionBump({
      commitLogPath,
      packageJsonPath,
      changelogPath: changelogPath ?? "CHANGELOG.md",
    });

    console.log(
      `Bumped version ${result.previousVersion} -> ${result.newVersion} (${result.bumpType})`,
    );
    console.log(`NEW_VERSION=${result.newVersion}`);

    // If running inside GitHub Actions, also expose the result as a step output.
    const githubOutput = process.env.GITHUB_OUTPUT;
    if (githubOutput) {
      writeFileSync(
        githubOutput,
        `new_version=${result.newVersion}\nbump_type=${result.bumpType}\nprevious_version=${result.previousVersion}\n`,
        { flag: "a" },
      );
    }
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    process.exit(1);
  }
}
