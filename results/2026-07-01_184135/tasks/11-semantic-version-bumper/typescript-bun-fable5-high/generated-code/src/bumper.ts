/**
 * GREEN phase (cycle 6): end-to-end orchestration.
 *
 * Approach: runBumper wires the pure pieces together —
 *   read version -> parse commits -> determine bump -> write version
 *   -> prepend changelog entry -> report old/new/bump.
 * A "none" bump is a successful no-op: nothing releasable happened, so no
 * file is touched and the version is reported unchanged.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { prependChangelogEntry, renderChangelogEntry } from "./changelog";
import { readCommitLogFile } from "./commitLog";
import { determineBump } from "./commits";
import { bumpVersion, formatVersion, type BumpType } from "./semver";
import { readVersionFile, writeVersionFile } from "./versionFile";

export interface BumperOptions {
  /** Path to VERSION file or package.json holding the current version. */
  versionFile: string;
  /** Path to the commit-log file (====COMMIT====-delimited messages). */
  commitsFile: string;
  /** Path to the changelog to prepend the release entry to. */
  changelogFile: string;
  /** Release date stamp (YYYY-MM-DD); injectable for deterministic tests. */
  date: string;
}

export interface BumperResult {
  oldVersion: string;
  newVersion: string;
  bump: BumpType;
}

/** Run the whole bump: mutates versionFile + changelogFile, returns the result. */
export function runBumper(opts: BumperOptions): BumperResult {
  const current = readVersionFile(opts.versionFile);
  const commits = readCommitLogFile(opts.commitsFile);
  const bump = determineBump(commits);
  const oldVersion = formatVersion(current);

  if (bump === "none") {
    // Nothing releasable — deliberately leave every file untouched.
    return { oldVersion, newVersion: oldVersion, bump };
  }

  const next = bumpVersion(current, bump);
  const newVersion = formatVersion(next);

  writeVersionFile(opts.versionFile, next);

  const existing = existsSync(opts.changelogFile)
    ? readFileSync(opts.changelogFile, "utf8")
    : "";
  const entry = renderChangelogEntry(newVersion, commits, opts.date);
  writeFileSync(opts.changelogFile, prependChangelogEntry(existing, entry));

  return { oldVersion, newVersion, bump };
}
