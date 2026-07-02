/**
 * GREEN phase (cycle 3): changelog rendering.
 *
 * Approach: bucket commits into Breaking/Features/Fixes/Other, render only
 * non-empty buckets as markdown sections, and prepend the finished entry
 * under a stable "# Changelog" title so newest releases read first.
 */
import type { ConventionalCommit } from "./commits";

const TITLE = "# Changelog";

/** Format one commit as a changelog bullet, bolding the scope if present. */
function bullet(c: ConventionalCommit): string {
  return c.scope ? `- **${c.scope}**: ${c.description}` : `- ${c.description}`;
}

/**
 * Render one release entry ("## <version> (<date>)" plus grouped sections).
 * `date` is injected by the caller so this stays pure and testable.
 */
export function renderChangelogEntry(
  version: string,
  commits: ConventionalCommit[],
  date: string,
): string {
  const sections: Array<[title: string, items: ConventionalCommit[]]> = [
    ["Breaking Changes", commits.filter((c) => c.breaking)],
    ["Features", commits.filter((c) => !c.breaking && c.type === "feat")],
    ["Fixes", commits.filter((c) => !c.breaking && c.type === "fix")],
    [
      "Other",
      commits.filter((c) => !c.breaking && c.type !== "feat" && c.type !== "fix"),
    ],
  ];

  let entry = `## ${version} (${date})\n`;
  for (const [title, items] of sections) {
    if (items.length === 0) continue;
    entry += `\n### ${title}\n\n${items.map(bullet).join("\n")}\n`;
  }
  return entry;
}

/**
 * Insert a new entry at the top of an existing changelog (or start a fresh
 * one). The "# Changelog" title always stays as the first line.
 */
export function prependChangelogEntry(existing: string, entry: string): string {
  const body = existing.replace(TITLE, "").trim();
  const tail = body.length > 0 ? `\n${body}\n` : "";
  return `${TITLE}\n\n${entry.trim()}\n${tail}`;
}
