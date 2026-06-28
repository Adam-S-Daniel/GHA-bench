// bumper.ts — orchestrate the full version-bump pipeline.
//
// This module is the seam the CLI and the test suite drive. It is pure with
// respect to the clock (the date is injected) and performs no console I/O, so
// it is easy to test deterministically.

import { generateChangelogEntry, prependChangelog } from "./changelog.ts";
import {
  determineBump,
  parseCommitLog,
  type ConventionalCommit,
} from "./commits.ts";
import { bumpVersion, formatVersion, parseVersion, type BumpType } from "./semver.ts";
import { readVersionFile, writeVersionFile } from "./version-file.ts";

/** Options controlling a bump run. */
export interface BumpOptions {
  /** Path to the version source (package.json or a plain version file). */
  versionFilePath: string;
  /** Path to the commit-log fixture/file to analyse. */
  commitsPath: string;
  /** Where to write the changelog (defaults to CHANGELOG.md beside the cwd). */
  changelogPath?: string;
  /** ISO date (YYYY-MM-DD) stamped on the changelog entry. */
  date: string;
  /** Delimiter separating commits in the log (defaults to the module default). */
  delimiter?: string;
  /** When true, compute everything but write nothing to disk. */
  dryRun?: boolean;
}

/** The outcome of a bump run, ready for the CLI to report. */
export interface BumpResult {
  previousVersion: string;
  newVersion: string;
  bump: BumpType;
  /** True when the bump actually changed the version. */
  changed: boolean;
  /** The rendered changelog entry (always computed, even in dry-run). */
  changelogEntry: string;
  /** The parsed commits considered for this release. */
  commits: ConventionalCommit[];
}

/**
 * Run the bump pipeline: read the version + commits, compute the next version,
 * render a changelog entry, and (unless dry-run) persist both files.
 */
export async function runBump(opts: BumpOptions): Promise<BumpResult> {
  // 1. Load the current version.
  const versionFile = await readVersionFile(opts.versionFilePath);
  const previous = parseVersion(versionFile.version);
  const previousVersion = formatVersion(previous);

  // 2. Load and classify the commits.
  const commitsFile = Bun.file(opts.commitsPath);
  if (!(await commitsFile.exists())) {
    throw new Error(`Commit log not found: ${opts.commitsPath}`);
  }
  const commits = parseCommitLog(await commitsFile.text(), opts.delimiter);
  const bump = determineBump(commits);

  // 3. Compute the next version.
  const next = bumpVersion(previous, bump);
  const newVersion = formatVersion(next);
  const changed = bump !== "none";

  // 4. Render the changelog entry for this release.
  const changelogEntry = generateChangelogEntry({
    version: newVersion,
    date: opts.date,
    commits,
  });

  // 5. Persist, unless this is a dry run or nothing changed.
  if (!opts.dryRun && changed) {
    await writeVersionFile(versionFile, newVersion);

    const changelogPath = opts.changelogPath ?? "CHANGELOG.md";
    const existing = (await Bun.file(changelogPath).exists())
      ? await Bun.file(changelogPath).text()
      : "";
    await Bun.write(changelogPath, prependChangelog(existing, changelogEntry));
  }

  return {
    previousVersion,
    newVersion,
    bump,
    changed,
    changelogEntry,
    commits,
  };
}
