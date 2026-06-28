// changelog.ts — render a "Keep a Changelog"-style entry from commits.
//
// The generated entry groups commits by Conventional Commit type into
// Breaking Changes / Features / Bug Fixes / Other Changes sections. The date
// is always passed in (never read from the system clock) so output is
// deterministic and unit-testable.

import type { ConventionalCommit } from "./commits.ts";

/** Inputs required to render one changelog entry. */
export interface ChangelogOptions {
  /** The new version string (without a leading "v"). */
  version: string;
  /** ISO date (YYYY-MM-DD) to stamp on the entry. */
  date: string;
  /** The commits included in this release. */
  commits: ConventionalCommit[];
}

/** Title + preamble used when bootstrapping a brand-new changelog file. */
export const CHANGELOG_HEADER =
  "# Changelog\n\n" +
  "All notable changes to this project are documented in this file.\n";

const BREAKING_NOTE_RE = /^BREAKING[ -]CHANGE:\s*(.*)$/m;

/** Render a single commit as a markdown bullet, prefixing the scope if any. */
function bullet(text: string, scope?: string): string {
  return scope ? `- **${scope}:** ${text}` : `- ${text}`;
}

/**
 * Extract the human-facing note for a breaking change: the text following a
 * "BREAKING CHANGE:" footer if present, otherwise the commit description.
 */
function breakingNote(commit: ConventionalCommit): string {
  const match = BREAKING_NOTE_RE.exec(commit.body) ?? BREAKING_NOTE_RE.exec(
    `${commit.subject}\n${commit.body}`,
  );
  const note = match?.[1]?.trim();
  return note && note.length > 0 ? note : commit.description;
}

/** Build one "### Heading\n\n- bullet\n- bullet" block, or "" if empty. */
function section(heading: string, bullets: string[]): string {
  if (bullets.length === 0) return "";
  return `### ${heading}\n\n${bullets.join("\n")}\n`;
}

/**
 * Render a changelog entry for a release. Sections are emitted in priority
 * order and omitted entirely when they would be empty.
 */
export function generateChangelogEntry(opts: ChangelogOptions): string {
  const { version, date, commits } = opts;

  const breaking = commits.filter((c) => c.breaking);
  const features = commits.filter((c) => c.type === "feat");
  const fixes = commits.filter((c) => c.type === "fix");
  // "Other" = any commit with a recognised type that is neither feat nor fix.
  const others = commits.filter(
    (c) => c.type !== "" && c.type !== "feat" && c.type !== "fix",
  );

  const blocks = [
    section(
      "⚠ BREAKING CHANGES",
      breaking.map((c) => bullet(breakingNote(c), c.scope)),
    ),
    section("Features", features.map((c) => bullet(c.description, c.scope))),
    section("Bug Fixes", fixes.map((c) => bullet(c.description, c.scope))),
    section("Other Changes", others.map((c) => bullet(c.description, c.scope))),
  ].filter((b) => b.length > 0);

  const heading = `## [${version}] - ${date}`;
  if (blocks.length === 0) {
    return `${heading}\n\n_No notable changes._\n`;
  }
  return `${heading}\n\n${blocks.join("\n")}`;
}

/**
 * Insert a new entry into an existing changelog, keeping the newest entry at
 * the top (directly under the title) and preserving older entries below.
 */
export function prependChangelog(existing: string, entry: string): string {
  const cleanEntry = entry.trim();
  const trimmed = existing.trim();

  // No file yet: bootstrap title + first entry.
  if (trimmed.length === 0) {
    return `${CHANGELOG_HEADER}\n${cleanEntry}\n`;
  }

  // Insert directly before the first existing version heading, if any.
  const firstEntryIdx = existing.search(/^## /m);
  if (firstEntryIdx === -1) {
    return `${existing.trimEnd()}\n\n${cleanEntry}\n`;
  }
  const head = existing.slice(0, firstEntryIdx).trimEnd();
  const tail = existing.slice(firstEntryIdx).trimEnd();
  return `${head}\n\n${cleanEntry}\n\n${tail}\n`;
}
