// Test fixture utilities

import { execSync } from "child_process";

// Execute a command in a given directory
export function commitExec(
  command: string,
  cwd: string = process.cwd()
): string {
  try {
    return execSync(command, { cwd, encoding: "utf-8" }).trim();
  } catch (error) {
    throw new Error(
      `Command failed: ${command}\n${error instanceof Error ? error.message : String(error)}`
    );
  }
}

// Sample git log output for testing
export const sampleGitLog = `feat(auth): add JWT support
fix: resolve memory leak
docs: update README
feat!: remove deprecated API
fix(perf): optimize query performance`;

// Sample conventional commits for testing
export const sampleCommits = [
  {
    type: "feat",
    scope: "auth",
    message: "add JWT support",
    isBreaking: false,
  },
  { type: "fix", scope: undefined, message: "resolve memory leak", isBreaking: false },
  { type: "docs", scope: undefined, message: "update README", isBreaking: false },
  { type: "feat", scope: undefined, message: "remove deprecated API", isBreaking: true },
  { type: "fix", scope: "perf", message: "optimize query performance", isBreaking: false },
];
