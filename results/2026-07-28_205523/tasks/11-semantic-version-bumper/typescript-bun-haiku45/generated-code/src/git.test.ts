import { expect, describe, it, beforeEach, afterEach } from "bun:test";
import { getCommitsSinceTag, initMockRepo, Commit } from "./git";
import { rmSync, mkdirSync } from "fs";

const testRepoDir = "/tmp/git-test-repo";

describe("git operations", () => {
  beforeEach(() => {
    try {
      rmSync(testRepoDir, { recursive: true, force: true });
    } catch {
      // Ignore
    }
    mkdirSync(testRepoDir, { recursive: true });
  });

  afterEach(() => {
    try {
      rmSync(testRepoDir, { recursive: true, force: true });
    } catch {
      // Ignore
    }
  });

  it("should initialize a mock git repository", () => {
    const result = initMockRepo(testRepoDir);
    expect(result).toContain("Initialized");
  });

  it("should get commits since a tag", () => {
    initMockRepo(testRepoDir);

    // Create some commits
    const commits: Commit[] = [
      { hash: "abc123def456", message: "feat: add feature", body: "" },
      { hash: "def456ghi789", message: "fix: fix bug", body: "" },
    ];

    const result = getCommitsSinceTag(testRepoDir, "v1.0.0", commits);

    expect(result.length).toBeGreaterThan(0);
    expect(result[0]).toEqual(commits[0]);
  });

  it("should return empty array for no commits", () => {
    initMockRepo(testRepoDir);

    const result = getCommitsSinceTag(testRepoDir, "v1.0.0", []);
    expect(result).toEqual([]);
  });

  it("should handle commit with multiline body", () => {
    initMockRepo(testRepoDir);

    const commit: Commit = {
      hash: "xyz789",
      message: "feat: major change",
      body: "BREAKING CHANGE: old API removed\nPlease migrate to new API",
    };

    const result = getCommitsSinceTag(testRepoDir, "v1.0.0", [commit]);

    expect(result[0].body).toContain("BREAKING CHANGE");
  });
});
