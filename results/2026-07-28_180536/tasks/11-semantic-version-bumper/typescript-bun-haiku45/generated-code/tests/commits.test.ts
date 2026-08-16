// TDD: Test commit parsing and version bump determination

import { expect, test, describe } from "bun:test";
import {
  parseCommitMessage,
  determineVersionBump,
  CommitType,
  Commit,
} from "../src/commits";
import { VersionBump } from "../src/semver";

describe("parseCommitMessage", () => {
  test("should parse conventional commit with feat type", () => {
    const commit = parseCommitMessage("feat: add new feature");
    expect(commit.type).toBe(CommitType.FEAT);
    expect(commit.message).toBe("add new feature");
  });

  test("should parse conventional commit with fix type", () => {
    const commit = parseCommitMessage("fix: resolve bug");
    expect(commit.type).toBe(CommitType.FIX);
    expect(commit.message).toBe("resolve bug");
  });

  test("should parse commit with breaking change", () => {
    const commit = parseCommitMessage(
      "feat!: breaking change in API"
    );
    expect(commit.type).toBe(CommitType.FEAT);
    expect(commit.isBreaking).toBe(true);
    expect(commit.message).toBe("breaking change in API");
  });

  test("should parse fix with breaking change", () => {
    const commit = parseCommitMessage(
      "fix!: remove deprecated field"
    );
    expect(commit.type).toBe(CommitType.FIX);
    expect(commit.isBreaking).toBe(true);
  });

  test("should parse commit with scope", () => {
    const commit = parseCommitMessage("feat(auth): add JWT support");
    expect(commit.type).toBe(CommitType.FEAT);
    expect(commit.scope).toBe("auth");
    expect(commit.message).toBe("add JWT support");
  });

  test("should handle commit with breaking change body", () => {
    const commit = parseCommitMessage(
      "feat: new API\n\nBREAKING CHANGE: old API removed"
    );
    expect(commit.isBreaking).toBe(true);
  });

  test("should parse docs and chore commits", () => {
    const docs = parseCommitMessage("docs: update README");
    expect(docs.type).toBe(CommitType.DOCS);

    const chore = parseCommitMessage("chore: bump dependencies");
    expect(chore.type).toBe(CommitType.CHORE);
  });

  test("should handle regular commits without type", () => {
    const commit = parseCommitMessage("Some regular commit message");
    expect(commit.type).toBe(CommitType.OTHER);
  });
});

describe("determineVersionBump", () => {
  test("should return NONE for empty commits", () => {
    const bump = determineVersionBump([]);
    expect(bump).toBe(VersionBump.NONE);
  });

  test("should return PATCH for fix commits only", () => {
    const commits: Commit[] = [
      { type: CommitType.FIX, message: "fix bug", isBreaking: false },
    ];
    const bump = determineVersionBump(commits);
    expect(bump).toBe(VersionBump.PATCH);
  });

  test("should return MINOR for feat commits", () => {
    const commits: Commit[] = [
      { type: CommitType.FEAT, message: "add feature", isBreaking: false },
    ];
    const bump = determineVersionBump(commits);
    expect(bump).toBe(VersionBump.MINOR);
  });

  test("should return MAJOR for breaking changes", () => {
    const commits: Commit[] = [
      { type: CommitType.FEAT, message: "breaking", isBreaking: true },
    ];
    const bump = determineVersionBump(commits);
    expect(bump).toBe(VersionBump.MAJOR);
  });

  test("should prioritize breaking change over feat", () => {
    const commits: Commit[] = [
      { type: CommitType.FIX, message: "fix", isBreaking: true },
      { type: CommitType.FEAT, message: "feat", isBreaking: false },
    ];
    const bump = determineVersionBump(commits);
    expect(bump).toBe(VersionBump.MAJOR);
  });

  test("should prioritize feat over fix", () => {
    const commits: Commit[] = [
      { type: CommitType.FIX, message: "fix", isBreaking: false },
      { type: CommitType.FEAT, message: "feat", isBreaking: false },
    ];
    const bump = determineVersionBump(commits);
    expect(bump).toBe(VersionBump.MINOR);
  });
});
