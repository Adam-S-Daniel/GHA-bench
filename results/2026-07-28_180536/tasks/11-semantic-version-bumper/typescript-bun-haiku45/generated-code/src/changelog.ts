// Changelog generation from commits

export { CommitType } from "./commits";
export type { Commit } from "./commits";

import { CommitType } from "./commits";
import type { Commit } from "./commits";

// Generate a changelog entry for a specific version
export function generateChangelogEntry(version: string, commits: Commit[]): string {
  const breaking = commits.filter((c) => c.isBreaking);
  const features = commits.filter(
    (c) => c.type === CommitType.FEAT && !c.isBreaking
  );
  const fixes = commits.filter(
    (c) => c.type === CommitType.FIX && !c.isBreaking
  );

  let entry = `## ${version}\n\n`;

  if (breaking.length > 0) {
    entry += `### BREAKING CHANGES\n\n`;
    breaking.forEach((c) => {
      const scopeStr = c.scope ? ` **${c.scope}:**` : "";
      entry += `- ${scopeStr} ${c.message}\n`;
    });
    entry += "\n";
  }

  if (features.length > 0) {
    entry += `### Features\n\n`;
    features.forEach((c) => {
      const scopeStr = c.scope ? ` **${c.scope}:**` : "";
      entry += `- ${scopeStr} ${c.message}\n`;
    });
    entry += "\n";
  }

  if (fixes.length > 0) {
    entry += `### Bug Fixes\n\n`;
    fixes.forEach((c) => {
      const scopeStr = c.scope ? ` **${c.scope}:**` : "";
      entry += `- ${scopeStr} ${c.message}\n`;
    });
    entry += "\n";
  }

  return entry;
}
