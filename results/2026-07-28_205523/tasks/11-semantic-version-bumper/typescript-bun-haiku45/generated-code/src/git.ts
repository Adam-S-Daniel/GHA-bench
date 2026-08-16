// Re-export commit type from commits module
export type { Commit } from "./commits";
import type { Commit } from "./commits";
import { execSync } from "child_process";

// Initialize a mock git repository for testing
export function initMockRepo(repoPath: string): string {
  try {
    execSync(`git init -q ${repoPath}`, { stdio: "pipe" });
    return "Initialized empty Git repository";
  } catch (error) {
    throw new Error(`Failed to initialize git repository: ${error}`);
  }
}

// Get commits since a specific tag (simulated)
// In a real scenario, this would parse git log output
export function getCommitsSinceTag(
  repoPath: string,
  tag: string,
  mockCommits: Commit[]
): Commit[] {
  // For testing purposes, we return the mock commits as-is
  // In production, this would actually call git log and parse the output
  return mockCommits;
}

// Parse git log output into commit objects
export function parseGitLog(logOutput: string): Commit[] {
  const commits: Commit[] = [];

  // Git log format: hash%n%s%n%b%n---END---
  const commitBlocks = logOutput.split("---END---").filter((b) => b.trim());

  for (const block of commitBlocks) {
    const lines = block.trim().split("\n");
    if (lines.length < 2) continue;

    const hash = lines[0].trim();
    const message = lines[1].trim();
    const body = lines.slice(2).join("\n").trim();

    commits.push({ hash, message, body });
  }

  return commits;
}
