// src/commits.ts
// Parse Conventional Commit messages (https://www.conventionalcommits.org/)
// and reduce a list of them to a single bump decision.
import type { BumpType } from "./semver.ts";

/** A single parsed commit message. */
export interface ParsedCommit {
  /** Conventional type, e.g. "feat", "fix", "chore". "other" if unconventional. */
  type: string;
  /** Optional scope captured from `type(scope):`, else null. */
  scope: string | null;
  /** The short description (the text after the colon on the header line). */
  description: string;
  /** True if the commit is a breaking change (`!` marker or BREAKING CHANGE footer). */
  breaking: boolean;
  /** The bump this single commit implies, before combining with others. */
  bump: BumpType;
  /** The raw, untouched message — handy for the changelog. */
  raw: string;
}

// Header grammar: type, optional (scope), optional !, ": ", description.
// Example matches: "feat: x", "fix(api): y", "refactor(core)!: z".
const HEADER_RE = /^([a-zA-Z]+)(?:\(([^)]+)\))?(!)?:\s*(.+)$/;

// A commit body/footer declaring a breaking change. Per the spec the token is
// "BREAKING CHANGE" (or the synonym "BREAKING-CHANGE").
const BREAKING_FOOTER_RE = /^BREAKING[ -]CHANGE:/m;

// Numeric precedence so we can pick the "highest" bump from a set of commits.
const BUMP_RANK: Record<BumpType, number> = {
  none: 0,
  patch: 1,
  minor: 2,
  major: 3,
};

/** Map a conventional type + breaking flag to the bump it implies. */
function bumpForType(type: string, breaking: boolean): BumpType {
  if (breaking) return "major";
  if (type === "feat") return "minor";
  if (type === "fix") return "patch";
  // chore, docs, style, refactor, perf, test, build, ci, "other", ... -> no release.
  return "none";
}

/**
 * Parse a single (possibly multi-line) commit message. The first line is the
 * header; any remaining lines are the body/footer, scanned for a breaking
 * change declaration.
 */
export function parseCommit(message: string): ParsedCommit {
  const raw = message;
  const trimmed = message.trim();
  const newlineIdx = trimmed.indexOf("\n");
  const header = (newlineIdx === -1 ? trimmed : trimmed.slice(0, newlineIdx)).trim();
  const body = newlineIdx === -1 ? "" : trimmed.slice(newlineIdx + 1);

  const match = HEADER_RE.exec(header);
  if (!match) {
    // Not a conventional commit — record it but treat it as non-release.
    return {
      type: "other",
      scope: null,
      description: header,
      breaking: false,
      bump: "none",
      raw,
    };
  }

  const type = match[1]!;
  const scope = match[2] ?? null;
  const bangMarker = match[3] === "!";
  const description = match[4]!.trim();
  const breaking = bangMarker || BREAKING_FOOTER_RE.test(body);

  return {
    type,
    scope,
    description,
    breaking,
    bump: bumpForType(type, breaking),
    raw,
  };
}

/**
 * Parse a whole commit log into individual commits.
 *
 * Two formats are accepted:
 *  - Simple: one commit per line (blank lines ignored). Good for single-line
 *    `git log --format=%s` output.
 *  - Record-delimited: commits separated by a line containing only `---`,
 *    allowing multi-line bodies (e.g. for BREAKING CHANGE footers).
 */
export function parseCommitLog(log: string): ParsedCommit[] {
  const normalized = log.replace(/\r\n/g, "\n");

  // If the delimiter is present, treat the log as record-delimited so that
  // bodies spanning multiple lines stay attached to their header.
  if (/^---$/m.test(normalized)) {
    return normalized
      .split(/^---$/m)
      .map((record) => record.trim())
      .filter((record) => record.length > 0)
      .map(parseCommit);
  }

  // Otherwise: one commit per non-blank line.
  return normalized
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map(parseCommit);
}

/**
 * Reduce a list of commits to the single highest-precedence bump.
 * Empty list (or all non-release commits) yields "none".
 */
export function determineBump(commits: ParsedCommit[]): BumpType {
  let best: BumpType = "none";
  for (const commit of commits) {
    if (BUMP_RANK[commit.bump] > BUMP_RANK[best]) {
      best = commit.bump;
    }
  }
  return best;
}
