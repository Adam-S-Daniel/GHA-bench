// Conventional commit parsing and analysis

import { VersionBump } from "./semver";

export enum CommitType {
  FEAT = "feat",
  FIX = "fix",
  DOCS = "docs",
  CHORE = "chore",
  REFACTOR = "refactor",
  PERF = "perf",
  TEST = "test",
  BUILD = "build",
  CI = "ci",
  OTHER = "other",
}

export interface Commit {
  type: CommitType;
  scope?: string;
  message: string;
  isBreaking: boolean;
  body?: string;
}

// Parse a conventional commit message
export function parseCommitMessage(fullMessage: string): Commit {
  const [firstLine, ...bodyLines] = fullMessage.split("\n");
  const body = bodyLines.join("\n");

  // Match pattern: type(scope)!: message or type!: message or type(scope): message or type: message
  const match = firstLine.match(
    /^([a-z]+)(\([^)]*\))?!?\s*:\s*(.+)$|^([a-z]+)!?\s*:\s*(.+)$/
  );

  if (!match) {
    return {
      type: CommitType.OTHER,
      message: firstLine,
      isBreaking: false,
    };
  }

  const type = (match[1] || match[4]) as CommitType | string;
  const scope = match[2]?.slice(1, -1); // Remove parentheses
  const message = match[3] || match[5];
  const isBreaking = firstLine.includes("!");

  // Check for BREAKING CHANGE in body
  const hasBreakingInBody = body.includes("BREAKING CHANGE:");

  return {
    type: (CommitType[type.toUpperCase() as keyof typeof CommitType] ||
      CommitType.OTHER) as CommitType,
    scope,
    message,
    isBreaking: isBreaking || hasBreakingInBody,
    body,
  };
}

// Determine what type of version bump is needed based on commits
export function determineVersionBump(commits: Commit[]): VersionBump {
  if (commits.length === 0) {
    return VersionBump.NONE;
  }

  // Check for breaking changes first (highest priority)
  if (commits.some((c) => c.isBreaking)) {
    return VersionBump.MAJOR;
  }

  // Check for features (second priority)
  if (commits.some((c) => c.type === CommitType.FEAT)) {
    return VersionBump.MINOR;
  }

  // Check for fixes (third priority)
  if (commits.some((c) => c.type === CommitType.FIX)) {
    return VersionBump.PATCH;
  }

  // All other commit types don't bump version
  return VersionBump.NONE;
}
