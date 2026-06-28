// commits.ts — parse Conventional Commit messages and map them to SemVer bumps.
//
// Reference: https://www.conventionalcommits.org/en/v1.0.0/
//
// Header grammar we support:
//   <type>[(scope)][!]: <description>
// The optional body/footer may carry a "BREAKING CHANGE:" (or
// "BREAKING-CHANGE:") notice, which forces a major bump regardless of type.

import type { BumpType } from "./semver.ts";

/** A single parsed commit and the bump it implies. */
export interface ConventionalCommit {
  /** Lower-cased type (e.g. "feat", "fix"). Empty string if non-conventional. */
  type: string;
  /** Optional scope captured from `type(scope):`. */
  scope?: string;
  /** True if the commit is a breaking change (`!` marker or BREAKING footer). */
  breaking: boolean;
  /** The description following the header prefix. */
  description: string;
  /** The full first line of the commit message. */
  subject: string;
  /** Everything after the first line (may be empty). */
  body: string;
  /** The SemVer bump implied by this single commit. */
  bump: BumpType;
}

/** Default delimiter line separating commits in a log fixture. */
export const DEFAULT_COMMIT_DELIMITER = "--COMMIT--";

// <type>(scope)!: description  — scope and "!" are optional.
const HEADER_RE = /^([A-Za-z]+)(?:\(([^)]+)\))?(!)?:\s*(.+)$/;

// A BREAKING CHANGE footer, per the spec, may use a space or a hyphen.
const BREAKING_RE = /^BREAKING[ -]CHANGE:/m;

/** Ranking used to pick the most significant bump. */
const BUMP_RANK: Record<BumpType, number> = {
  none: 0,
  patch: 1,
  minor: 2,
  major: 3,
};

/** Map a commit's type + breaking flag to the bump it implies. */
function bumpForCommit(type: string, breaking: boolean): BumpType {
  if (breaking) return "major";
  if (type === "feat") return "minor";
  if (type === "fix") return "patch";
  return "none";
}

/** Parse a single (possibly multi-line) commit message. */
export function parseCommitMessage(message: string): ConventionalCommit {
  const normalised = message.replace(/\r\n/g, "\n").trim();
  const newlineIndex = normalised.indexOf("\n");
  const subject =
    newlineIndex === -1 ? normalised : normalised.slice(0, newlineIndex);
  const body =
    newlineIndex === -1 ? "" : normalised.slice(newlineIndex + 1).trim();

  const match = HEADER_RE.exec(subject);
  // A breaking change is signalled either by "!" in the header or by a
  // BREAKING CHANGE footer anywhere in the message.
  const breakingFooter = BREAKING_RE.test(normalised);

  if (!match) {
    // Non-conventional commit: keep the text but treat it as non-releasing,
    // unless it carries an explicit BREAKING CHANGE footer.
    return {
      type: "",
      scope: undefined,
      breaking: breakingFooter,
      description: subject,
      subject,
      body,
      bump: bumpForCommit("", breakingFooter),
    };
  }

  const [, rawType, scope, bang, description] = match;
  const type = rawType!.toLowerCase();
  const breaking = Boolean(bang) || breakingFooter;

  return {
    type,
    scope: scope,
    breaking,
    description: description!,
    subject,
    body,
    bump: bumpForCommit(type, breaking),
  };
}

/**
 * Parse a delimited commit log into individual commits. Blocks are separated
 * by a line equal to `delimiter`. Blank blocks are skipped so trailing or
 * repeated delimiters are harmless.
 */
export function parseCommitLog(
  raw: string,
  delimiter: string = DEFAULT_COMMIT_DELIMITER,
): ConventionalCommit[] {
  return raw
    .replace(/\r\n/g, "\n")
    .split(new RegExp(`^${escapeRegExp(delimiter)}$`, "m"))
    .map((block) => block.trim())
    .filter((block) => block.length > 0)
    .map(parseCommitMessage);
}

/** Aggregate the highest-precedence bump across a list of commits. */
export function determineBump(commits: ConventionalCommit[]): BumpType {
  let result: BumpType = "none";
  for (const commit of commits) {
    if (BUMP_RANK[commit.bump] > BUMP_RANK[result]) {
      result = commit.bump;
    }
  }
  return result;
}

/** Escape a string for safe inclusion in a RegExp. */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
