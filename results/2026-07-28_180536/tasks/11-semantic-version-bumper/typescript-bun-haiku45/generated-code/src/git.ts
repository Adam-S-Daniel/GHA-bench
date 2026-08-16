// Git utilities for retrieving commit history

import { execSync } from "child_process";
import { parseCommitMessage, Commit } from "./commits";

// Get commits since a specific tag
export function getCommitsSinceTag(
  repoPath: string,
  tag: string
): Commit[] {
  try {
    // First check if tag exists
    execSync(`git -C "${repoPath}" rev-parse ${tag}`, {
      encoding: "utf-8",
      stdio: "ignore",
    });

    // Tag exists, get commits since tag
    const command = `git -C "${repoPath}" log --pretty=format:%B ${tag}..HEAD`;
    const output = execSync(command, { encoding: "utf-8" }).trim();

    if (!output) {
      return [];
    }

    return parseCommitLog(output);
  } catch (error) {
    // If tag doesn't exist, try getting all commits
    try {
      const command = `git -C "${repoPath}" log --pretty=format:%B`;
      const output = execSync(command, { encoding: "utf-8" }).trim();
      if (!output) {
        return [];
      }
      return parseCommitLog(output);
    } catch {
      return [];
    }
  }
}

// Parse git log output into commits
export function parseCommitLog(gitLog: string): Commit[] {
  if (!gitLog.trim()) {
    return [];
  }

  // Split by double newlines (which separate commits in git log output)
  // or by single newlines if they're commit messages (starting with type:)
  const lines = gitLog.split("\n").filter((line) => line.trim().length > 0);

  // Try to identify commit boundaries
  // Commits start with conventional commit types
  const commitMessages: string[] = [];
  let currentMessage = "";

  for (const line of lines) {
    // Check if this line starts a new commit (conventional commit pattern)
    if (
      /^(feat|fix|docs|chore|refactor|perf|test|build|ci|style)(\([^)]*\))?!?:/.test(
        line
      )
    ) {
      if (currentMessage.trim()) {
        commitMessages.push(currentMessage.trim());
      }
      currentMessage = line;
    } else {
      // This is a continuation of the current commit message
      if (currentMessage) {
        currentMessage += "\n" + line;
      }
    }
  }

  if (currentMessage.trim()) {
    commitMessages.push(currentMessage.trim());
  }

  return commitMessages.map((msg) => parseCommitMessage(msg));
}
