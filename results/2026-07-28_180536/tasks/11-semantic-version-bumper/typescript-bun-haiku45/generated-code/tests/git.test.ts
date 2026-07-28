// TDD: Test git utilities

import { expect, test, describe, beforeEach, afterEach } from "bun:test";
import { getCommitsSinceTag, parseCommitLog } from "../src/git";
import { commitExec } from "./test-fixtures";
import { CommitType } from "../src/commits";
import { mkdtempSync, rmSync } from "fs";
import { join } from "path";

describe("parseCommitLog", () => {
  test("should parse a single commit line", () => {
    const log = "feat: add new feature";
    const commits = parseCommitLog(log);
    expect(commits).toHaveLength(1);
    expect(commits[0].type).toBe(CommitType.FEAT);
    expect(commits[0].message).toBe("add new feature");
  });

  test("should parse multiple commits", () => {
    const log = `feat: add feature 1
fix: fix bug 1
feat(scope): add feature 2`;
    const commits = parseCommitLog(log);
    expect(commits).toHaveLength(3);
    expect(commits[0].type).toBe(CommitType.FEAT);
    expect(commits[1].type).toBe(CommitType.FIX);
    expect(commits[2].scope).toBe("scope");
  });

  test("should handle multiline commit messages", () => {
    const log = `feat: new feature
BREAKING CHANGE: this breaks things`;
    const commits = parseCommitLog(log);
    expect(commits).toHaveLength(1);
    expect(commits[0].isBreaking).toBe(true);
  });
});

describe("getCommitsSinceTag", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync("/tmp/git-test-");
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  test("should retrieve commits since a tag", () => {
    // Initialize a git repo
    commitExec("git init", tempDir);
    commitExec("git config user.email test@test.com", tempDir);
    commitExec("git config user.name Test", tempDir);

    // Create initial commit and tag
    commitExec("echo 'initial' > file.txt", tempDir);
    commitExec("git add file.txt", tempDir);
    commitExec("git commit -m 'initial: setup'", tempDir);
    commitExec("git tag v1.0.0", tempDir);

    // Add feature commit
    commitExec("echo 'feature' >> file.txt", tempDir);
    commitExec("git add file.txt", tempDir);
    commitExec("git commit -m 'feat: add feature'", tempDir);

    const commits = getCommitsSinceTag(tempDir, "v1.0.0");
    expect(commits).toHaveLength(1);
    expect(commits[0].type).toBe(CommitType.FEAT);
  });

  test("should handle non-existent tag", () => {
    commitExec("git init", tempDir);
    commitExec("git config user.email test@test.com", tempDir);
    commitExec("git config user.name Test", tempDir);

    commitExec("echo 'initial' > file.txt", tempDir);
    commitExec("git add file.txt", tempDir);
    commitExec("git commit -m 'feat: test'", tempDir);

    // Should get all commits if tag doesn't exist
    const commits = getCommitsSinceTag(tempDir, "nonexistent-tag");
    expect(commits.length).toBeGreaterThanOrEqual(1);
  });
});
