#!/usr/bin/env bun
// semantic-version-bumper CLI.
//
// Reads the current version, parses a commit log (one subject per line,
// conventional-commit style), decides the bump (breaking -> major,
// feat -> minor, fix -> patch), rewrites the version file, prepends a
// changelog entry, and prints the new version as the LAST line of stdout
// so callers (like the CI workflow) can capture it with `tail -n 1`.
//
// Usage:
//   bun run src/cli.ts --version-file package.json --commits commits.txt \
//     [--changelog CHANGELOG.md] [--date YYYY-MM-DD] [--dry-run]

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { parseCommits, determineBumpType } from "./commits";
import { bumpVersion } from "./semver";
import { generateChangelogEntry, prependChangelog } from "./changelog";
import { readVersion, writeVersion } from "./versionfile";

interface CliOptions {
  versionFile: string;
  commitsFile: string;
  changelogFile: string;
  date: string;
  dryRun: boolean;
}

/** Minimal flag parser; throws on unknown flags or missing values. */
function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    versionFile: "package.json",
    commitsFile: "",
    changelogFile: "CHANGELOG.md",
    date: new Date().toISOString().slice(0, 10),
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const next = (): string => {
      const value = argv[++i];
      if (value === undefined) throw new Error(`Missing value for ${flag}`);
      return value;
    };
    switch (flag) {
      case "--version-file": opts.versionFile = next(); break;
      case "--commits": opts.commitsFile = next(); break;
      case "--changelog": opts.changelogFile = next(); break;
      case "--date": opts.date = next(); break;
      case "--dry-run": opts.dryRun = true; break;
      default: throw new Error(`Unknown argument: ${flag}`);
    }
  }

  if (!opts.commitsFile) {
    throw new Error("Missing required --commits <file> (a commit log, one subject per line)");
  }
  return opts;
}

function main(): void {
  const opts = parseArgs(process.argv.slice(2));

  if (!existsSync(opts.commitsFile)) {
    throw new Error(`Commit log file not found: ${opts.commitsFile}`);
  }

  const currentVersion = readVersion(opts.versionFile);
  const commits = parseCommits(readFileSync(opts.commitsFile, "utf8"));
  const bump = determineBumpType(commits);

  if (bump === null) {
    console.log(`Current version ${currentVersion}: no releasable commits, no version bump.`);
    return;
  }

  const newVersion = bumpVersion(currentVersion, bump);
  console.log(`Bump type: ${bump} (${currentVersion} -> ${newVersion})`);

  if (!opts.dryRun) {
    writeVersion(opts.versionFile, newVersion);

    const existing = existsSync(opts.changelogFile)
      ? readFileSync(opts.changelogFile, "utf8")
      : "";
    const entry = generateChangelogEntry(newVersion, commits, opts.date);
    writeFileSync(opts.changelogFile, prependChangelog(existing, entry));
    console.log(`Updated ${opts.versionFile} and ${opts.changelogFile}`);
  }

  // The new version is always the final stdout line — the machine-readable output.
  console.log(newVersion);
}

try {
  main();
} catch (err) {
  console.error(`Error: ${(err as Error).message}`);
  process.exit(1);
}
