// src/changelog.ts
// Render a single "Keep a Changelog"-style entry from parsed commits.
import type { ParsedCommit } from "./commits.ts";

/**
 * Format a single commit as a markdown bullet. A scope, if present, is rendered
 * in bold as a prefix — e.g. "- **auth:** add OAuth login".
 */
function bullet(commit: ParsedCommit): string {
  const scopePrefix = commit.scope ? `**${commit.scope}:** ` : "";
  return `- ${scopePrefix}${commit.description}`;
}

/**
 * Build a changelog entry for `version`, released on `date` (ISO yyyy-mm-dd),
 * grouping the supplied commits into Breaking Changes / Features / Bug Fixes.
 * Non-release commits (chore, docs, ...) are intentionally excluded from the
 * body so the changelog stays focused on user-facing changes.
 */
export function generateChangelogEntry(
  version: string,
  commits: ParsedCommit[],
  date: string,
): string {
  // A breaking commit may also be a feat/fix; we surface it under Breaking
  // Changes so it is never buried. The remaining feats/fixes are grouped by type.
  const breaking = commits.filter((c) => c.breaking);
  const features = commits.filter((c) => c.type === "feat" && !c.breaking);
  const fixes = commits.filter((c) => c.type === "fix" && !c.breaking);

  const lines: string[] = [`## [${version}] - ${date}`, ""];

  const sections: Array<{ heading: string; items: ParsedCommit[] }> = [
    { heading: "### ⚠ Breaking Changes", items: breaking },
    { heading: "### Features", items: features },
    { heading: "### Bug Fixes", items: fixes },
  ];

  let wroteAnything = false;
  for (const { heading, items } of sections) {
    if (items.length === 0) continue;
    wroteAnything = true;
    lines.push(heading, "");
    for (const item of items) lines.push(bullet(item));
    lines.push("");
  }

  if (!wroteAnything) {
    lines.push("_No notable changes._", "");
  }

  // Trim the trailing blank line into a single terminating newline.
  return lines.join("\n").replace(/\n+$/, "\n");
}
