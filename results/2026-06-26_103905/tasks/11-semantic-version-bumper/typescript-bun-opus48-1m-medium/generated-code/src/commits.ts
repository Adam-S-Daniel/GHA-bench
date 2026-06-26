// Conventional-commit parsing and bump-precedence resolution.
import type { BumpType } from "./semver";

/** A single parsed commit message. */
export interface Commit {
  /** Conventional type (feat, fix, chore, ...) or "other" if unrecognised. */
  type: string;
  /** Optional scope captured from "type(scope):". */
  scope: string | null;
  /** The human-readable description after the colon. */
  subject: string;
  /** True when the commit declares a breaking change ("!" or footer). */
  breaking: boolean;
}

// Matches "type(scope)!: subject" where scope and "!" are optional.
const CONVENTIONAL_RE =
  /^(?<type>\w+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?:\s*(?<subject>.+)$/;

/**
 * Parse a newline-delimited commit log into structured {@link Commit}s.
 * Lines that do not match the conventional format are recorded as
 * type "other" so they can still appear in the changelog.
 */
export function parseCommits(log: string): Commit[] {
  return log
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map(parseLine);
}

function parseLine(line: string): Commit {
  const match = CONVENTIONAL_RE.exec(line);
  if (!match || !match.groups) {
    return { type: "other", scope: null, subject: line, breaking: false };
  }
  const { type, scope, bang, subject } = match.groups;
  // A breaking change is flagged either by "!" or a "BREAKING CHANGE" footer.
  const breaking = Boolean(bang) || /BREAKING[ -]CHANGE/i.test(line);
  return {
    type: type!.toLowerCase(),
    scope: scope ?? null,
    subject: subject!.trim(),
    breaking,
  };
}

/**
 * Resolve the highest-precedence bump implied by a set of commits.
 * Returns null when nothing warrants a release.
 */
export function determineBump(commits: Commit[]): BumpType | null {
  let bump: BumpType | null = null;
  for (const commit of commits) {
    if (commit.breaking) {
      return "major"; // Highest precedence — short-circuit immediately.
    }
    if (commit.type === "feat") {
      bump = "minor";
    } else if (commit.type === "fix" && bump !== "minor") {
      bump = "patch";
    }
  }
  return bump;
}
