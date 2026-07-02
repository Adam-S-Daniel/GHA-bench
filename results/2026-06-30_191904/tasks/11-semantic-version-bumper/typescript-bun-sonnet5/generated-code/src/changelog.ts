// Renders a Keep-a-Changelog-style (https://keepachangelog.com) entry for a
// version bump from the conventional commits that produced it.
import type { Commit } from "./commits.ts";

const CONVENTIONAL_HEADER = /^(\w+)(\(([^)]*)\))?(!)?:\s*(.+)/;

interface CategorizedLine {
  scope: string | undefined;
  description: string;
  hash: string;
}

function formatLine({ scope, description, hash }: CategorizedLine): string {
  const short = hash.slice(0, 7);
  return scope
    ? `- ${scope}: ${description} (${short})`
    : `- ${description} (${short})`;
}

const SECTIONS: { title: string; type: string }[] = [
  { title: "Features", type: "feat" },
  { title: "Fixes", type: "fix" },
];

/**
 * Builds a changelog entry for `version`, grouping commits into
 * "Breaking Changes", "Features", and "Fixes" sections (in that order),
 * skipping any section with no matching commits. Non-conventional commits
 * (e.g. "chore:", "docs:") are omitted from the body; if no commit is
 * conventional at all, a "No notable changes." placeholder is used.
 */
export function generateChangelogEntry(
  version: string,
  date: string,
  commits: Commit[],
): string {
  const breaking: CategorizedLine[] = [];
  const byType = new Map<string, CategorizedLine[]>(
    SECTIONS.map((s) => [s.type, []]),
  );

  for (const commit of commits) {
    const match = CONVENTIONAL_HEADER.exec(commit.subject);
    if (!match) continue;
    const [, type, , scope, breakingMarker, description] = match;
    const line: CategorizedLine = { scope, description: description!, hash: commit.hash };
    const isBreaking =
      breakingMarker === "!" || /^BREAKING[ -]CHANGE:/m.test(commit.body);

    if (isBreaking) {
      breaking.push(line);
    } else if (byType.has(type!)) {
      byType.get(type!)!.push(line);
    }
  }

  const sections: string[] = [];
  if (breaking.length > 0) {
    sections.push(
      ["### Breaking Changes", "", ...breaking.map(formatLine)].join("\n"),
    );
  }
  for (const { title, type } of SECTIONS) {
    const lines = byType.get(type)!;
    if (lines.length > 0) {
      sections.push([`### ${title}`, "", ...lines.map(formatLine)].join("\n"));
    }
  }

  const header = `## [${version}] - ${date}`;
  const body = sections.length > 0 ? sections.join("\n\n") : "No notable changes.";
  return `${header}\n\n${body}\n`;
}
