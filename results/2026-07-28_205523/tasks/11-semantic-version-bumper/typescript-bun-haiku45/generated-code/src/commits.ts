// Type definitions for git commits
export interface Commit {
  hash: string;
  message: string;
  body: string;
}

type BumpLevel = "major" | "minor" | "patch";

// Determine bump type for a single commit based on conventional commits
export function parseCommit(commit: Commit): BumpLevel {
  const { message, body } = commit;

  // Check for breaking change in message (feat!: ...) or body
  if (message.includes("!:") || body.includes("BREAKING CHANGE")) {
    return "major";
  }

  // Extract commit type (feat, fix, etc.)
  const typeMatch = message.match(/^(\w+)(?:\(.+\))?:/);
  if (!typeMatch) {
    return "patch";
  }

  const type = typeMatch[1];

  switch (type) {
    case "feat":
      return "minor";
    case "fix":
      return "patch";
    default:
      return "patch";
  }
}

// Determine the highest bump type from a list of commits
export function determineBumpType(commits: Commit[]): BumpLevel {
  const bumpPriority: Record<BumpLevel, number> = {
    major: 3,
    minor: 2,
    patch: 1,
  };

  let maxBump: BumpLevel = "patch";
  let maxPriority = 1;

  for (const commit of commits) {
    const bump = parseCommit(commit);
    const priority = bumpPriority[bump];

    if (priority > maxPriority) {
      maxPriority = priority;
      maxBump = bump;
    }
  }

  return maxBump;
}
