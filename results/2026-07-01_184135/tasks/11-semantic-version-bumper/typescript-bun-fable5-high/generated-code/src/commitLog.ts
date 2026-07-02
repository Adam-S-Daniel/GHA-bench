/**
 * GREEN phase (cycle 5): mock commit-log reading.
 *
 * Approach: fixture files hold full commit messages separated by a
 * "====COMMIT====" line (the shape `git log --format=%B%n====COMMIT====`
 * emits), so test fixtures stay human-readable while still supporting
 * multi-line bodies with BREAKING CHANGE footers.
 */
import { existsSync, readFileSync } from "node:fs";
import { parseCommit, type ConventionalCommit } from "./commits";

export const COMMIT_DELIMITER = "====COMMIT====";

/** Split raw log text into parsed commits, dropping empty segments. */
export function parseCommitLog(raw: string): ConventionalCommit[] {
  return raw
    .split(new RegExp(`^${COMMIT_DELIMITER}$`, "m"))
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0)
    .map(parseCommit);
}

/** Read and parse a commit-log fixture file. */
export function readCommitLogFile(path: string): ConventionalCommit[] {
  if (!existsSync(path)) {
    throw new Error(`Commit log file not found: "${path}"`);
  }
  return parseCommitLog(readFileSync(path, "utf8"));
}
