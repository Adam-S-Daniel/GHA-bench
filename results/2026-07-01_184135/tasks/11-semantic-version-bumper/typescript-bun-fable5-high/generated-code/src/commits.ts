/**
 * GREEN phase (cycle 2): conventional-commit parsing and bump determination.
 *
 * Approach: parse each raw commit message into a small typed record, then
 * fold the list into a single BumpType using precedence
 * breaking > feat > fix > none. Non-conventional messages are kept (they
 * still appear in the changelog under "Other") but never trigger a bump.
 */
import type { BumpType } from "./semver";

/** One parsed conventional commit. */
export interface ConventionalCommit {
  /** Commit type ("feat", "fix", ...) or "other" for non-conventional. */
  type: string;
  /** Scope inside parentheses, or null if absent. */
  scope: string | null;
  /** Text after the "type(scope): " prefix (or the whole subject). */
  description: string;
  /** True when "!" marker or a BREAKING CHANGE footer is present. */
  breaking: boolean;
  /** The original, unmodified message (first line kept in changelog). */
  raw: string;
}

// type, optional (scope), optional !, then ": description"
const HEADER_RE = /^([a-zA-Z]+)(?:\(([^)]*)\))?(!)?:\s+(.+)$/;
const BREAKING_FOOTER_RE = /^BREAKING[ -]CHANGE:/m;

/** Parse one raw commit message (subject + optional body). */
export function parseCommit(message: string): ConventionalCommit {
  const raw = message.trim();
  const subject = raw.split("\n", 1)[0] ?? "";
  const footerBreaking = BREAKING_FOOTER_RE.test(raw);

  const match = HEADER_RE.exec(subject);
  if (!match) {
    // Not a conventional commit — keep it, but it never drives a bump.
    return {
      type: "other",
      scope: null,
      description: subject,
      breaking: footerBreaking,
      raw,
    };
  }

  return {
    type: match[1]!.toLowerCase(),
    scope: match[2] ?? null,
    description: match[4]!,
    breaking: match[3] === "!" || footerBreaking,
    raw,
  };
}

/**
 * Fold a list of commits into the single strongest bump:
 * any breaking commit -> major; else any feat -> minor; else any fix -> patch;
 * else none (nothing releasable).
 */
export function determineBump(commits: ConventionalCommit[]): BumpType {
  let bump: BumpType = "none";
  for (const c of commits) {
    if (c.breaking) return "major"; // nothing outranks breaking
    if (c.type === "feat") bump = "minor";
    else if (c.type === "fix" && bump !== "minor") bump = "patch";
  }
  return bump;
}
