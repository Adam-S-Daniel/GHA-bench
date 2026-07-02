// Parsing of mock commit logs and rendering of changelog entries.

/** Splits raw commit log text into individual commit messages, dropping blank lines and comments. */
export function parseCommitLog(raw: string): string[] {
  return raw
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"));
}

export interface ChangelogInput {
  version: string;
  date: string;
  commits: string[];
}

const TYPE_HEADINGS: Record<string, string> = {
  feat: "Features",
  fix: "Fixes",
};

const CONVENTIONAL_COMMIT_PATTERN = /^(\w+)(\([^)]*\))?(!)?:\s*(.+)$/;

/** Renders a changelog entry, grouping commits by conventional-commit type. */
export function generateChangelogEntry(input: ChangelogInput): string {
  const groups = new Map<string, string[]>();

  for (const commit of input.commits) {
    const match = CONVENTIONAL_COMMIT_PATTERN.exec(commit.trim());
    const type = match?.[1] ?? "other";
    const description = match?.[4] ?? commit.trim();
    const heading = TYPE_HEADINGS[type] ?? "Other";

    if (!groups.has(heading)) {
      groups.set(heading, []);
    }
    groups.get(heading)!.push(description);
  }

  const lines: string[] = [`## ${input.version} (${input.date})`, ""];

  // Fixed ordering so entries are stable regardless of Map insertion order.
  const order = ["Features", "Fixes", "Other"];
  for (const heading of order) {
    const items = groups.get(heading);
    if (!items || items.length === 0) continue;
    lines.push(`### ${heading}`);
    for (const item of items) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  return lines.join("\n");
}
