// Changelog rendering: turn parsed commits into a markdown entry and
// prepend it to an existing CHANGELOG under the "# Changelog" title.

import type { ConventionalCommit } from "./commits";

interface Section {
  heading: string;
  include: (c: ConventionalCommit) => boolean;
}

// Order matters: a breaking feat appears only under Breaking Changes.
const SECTIONS: Section[] = [
  { heading: "Breaking Changes", include: (c) => c.breaking },
  { heading: "Features", include: (c) => !c.breaking && c.type === "feat" },
  { heading: "Fixes", include: (c) => !c.breaking && c.type === "fix" },
];

function renderCommit(c: ConventionalCommit): string {
  return c.scope ? `- **${c.scope}**: ${c.description}` : `- ${c.description}`;
}

/**
 * Render one release entry. Only breaking/feat/fix commits appear; empty
 * sections are omitted entirely.
 */
export function generateChangelogEntry(
  version: string,
  commits: ConventionalCommit[],
  date: string,
): string {
  const parts: string[] = [`## ${version} (${date})`];

  for (const section of SECTIONS) {
    const lines = commits.filter(section.include).map(renderCommit);
    if (lines.length > 0) {
      parts.push(`### ${section.heading}`, lines.join("\n"));
    }
  }

  return parts.join("\n\n") + "\n";
}

/**
 * Insert a new entry at the top of the changelog body, keeping (or creating)
 * the "# Changelog" title line so newest releases always come first.
 */
export function prependChangelog(existing: string, entry: string): string {
  const TITLE = "# Changelog";
  const body = existing.startsWith(TITLE) ? existing.slice(TITLE.length).trimStart() : existing.trimStart();
  return body === ""
    ? `${TITLE}\n\n${entry}`
    : `${TITLE}\n\n${entry}\n${body}`;
}
