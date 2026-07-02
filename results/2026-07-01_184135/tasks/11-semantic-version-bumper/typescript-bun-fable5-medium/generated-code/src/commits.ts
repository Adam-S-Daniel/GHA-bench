// Conventional-commit parsing and release-type decision.
//
// The commit log format is one commit subject per line (the shape produced
// by `git log --pretty=%s`, and the shape of the fixtures in fixtures/).
// A line starting with "BREAKING CHANGE:" is treated as a footer belonging
// to the commit above it rather than as a commit of its own.

import type { BumpType } from "./semver";

/** One parsed conventional commit. */
export interface ConventionalCommit {
  /** Conventional type ("feat", "fix", ...) or "other" for free-form messages. */
  type: string;
  /** Scope inside parentheses, if present. */
  scope: string | null;
  /** True for "type!:" subjects or commits with a BREAKING CHANGE footer. */
  breaking: boolean;
  /** Text after the "type(scope): " prefix (or the whole line for "other"). */
  description: string;
  /** The original subject line, unmodified. */
  raw: string;
}

const SUBJECT_RE = /^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$/;
const BREAKING_FOOTER_RE = /^BREAKING[ -]CHANGE:/i;

/** Parse a commit log (one subject per line) into structured commits. */
export function parseCommits(log: string): ConventionalCommit[] {
  const commits: ConventionalCommit[] = [];

  for (const rawLine of log.split("\n")) {
    const line = rawLine.trim();
    if (line === "") continue;

    // A BREAKING CHANGE footer flags the commit it belongs to as breaking.
    if (BREAKING_FOOTER_RE.test(line)) {
      const previous = commits[commits.length - 1];
      if (previous) previous.breaking = true;
      continue;
    }

    const match = SUBJECT_RE.exec(line);
    if (match) {
      commits.push({
        type: match[1].toLowerCase(),
        scope: match[2] ?? null,
        breaking: match[3] === "!",
        description: match[4],
        raw: line,
      });
    } else {
      // Non-conventional messages are kept (for the changelog) but never
      // influence the version bump.
      commits.push({ type: "other", scope: null, breaking: false, description: line, raw: line });
    }
  }

  return commits;
}

/**
 * Decide the release type: any breaking commit -> major, else any feat ->
 * minor, else any fix -> patch, else no release (null).
 */
export function determineBumpType(commits: ConventionalCommit[]): BumpType | null {
  if (commits.some((c) => c.breaking)) return "major";
  if (commits.some((c) => c.type === "feat")) return "minor";
  if (commits.some((c) => c.type === "fix")) return "patch";
  return null;
}
