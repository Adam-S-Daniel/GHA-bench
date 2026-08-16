// Re-export commit type for convenience
export type { Commit } from "./commits";
import type { Commit } from "./commits";

interface ChangelogSection {
  title: string;
  commits: Commit[];
}

function getCommitDescription(message: string): string {
  // Remove conventional commit prefix (feat:, fix:, etc.)
  return message.replace(/^(\w+)(?:\(.+\))?(?:!)?:\s*/, "");
}

function shortHash(hash: string): string {
  return hash.slice(0, 7);
}

export function generateChangelogEntry(
  version: string,
  commits: Commit[]
): string {
  const sections: ChangelogSection[] = [];

  // Separate commits by type
  const features = commits.filter((c) =>
    c.message.match(/^feat(?:\(.+\))?(?:!)?:/)
  );
  const fixes = commits.filter((c) => c.message.match(/^fix(?:\(.+\))?:/));
  const others = commits.filter(
    (c) => !c.message.match(/^(feat|fix)(?:\(.+\))?(?:!)?:/)
  );

  if (features.length > 0) {
    sections.push({ title: "Features", commits: features });
  }
  if (fixes.length > 0) {
    sections.push({ title: "Bug Fixes", commits: fixes });
  }
  if (others.length > 0) {
    sections.push({ title: "Other Changes", commits: others });
  }

  // Build changelog entry
  let entry = `## [${version}]\n\n`;

  if (sections.length === 0) {
    return entry;
  }

  for (const section of sections) {
    entry += `### ${section.title}\n\n`;
    for (const commit of section.commits) {
      const desc = getCommitDescription(commit.message);
      entry += `- ${desc} (${shortHash(commit.hash)})\n`;
    }
    entry += "\n";
  }

  return entry;
}
