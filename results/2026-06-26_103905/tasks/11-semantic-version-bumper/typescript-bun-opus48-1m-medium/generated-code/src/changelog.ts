// Changelog entry generation from parsed commits.
import type { Commit } from "./commits";

/** Render a single commit as a bullet, prefixing the scope when present. */
function bullet(commit: Commit): string {
  const scopePrefix = commit.scope ? `**${commit.scope}:** ` : "";
  return `- ${scopePrefix}${commit.subject}`;
}

/**
 * Build a Markdown changelog entry for a release.
 *
 * Commits are grouped into Breaking Changes / Features / Fixes / Other.
 * Empty sections are omitted entirely. The `date` is supplied by the caller
 * (rather than read from the clock) to keep this function pure and testable.
 */
export function generateChangelog(
  version: string,
  commits: Commit[],
  date: string,
): string {
  const breaking = commits.filter((c) => c.breaking);
  const features = commits.filter((c) => c.type === "feat" && !c.breaking);
  const fixes = commits.filter((c) => c.type === "fix" && !c.breaking);
  const other = commits.filter(
    (c) => !c.breaking && c.type !== "feat" && c.type !== "fix",
  );

  const lines: string[] = [`## ${version} (${date})`, ""];

  const section = (title: string, items: Commit[]): void => {
    if (items.length === 0) return;
    lines.push(`### ${title}`, "");
    for (const c of items) lines.push(bullet(c));
    lines.push("");
  };

  section("Breaking Changes", breaking);
  section("Features", features);
  section("Fixes", fixes);
  section("Other", other);

  // Trim trailing blank line for a tidy single entry.
  return lines.join("\n").trimEnd() + "\n";
}
