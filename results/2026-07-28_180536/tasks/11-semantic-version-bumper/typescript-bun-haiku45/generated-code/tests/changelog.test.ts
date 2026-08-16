// TDD: Test changelog generation

import { expect, test, describe } from "bun:test";
import { generateChangelogEntry, Commit } from "../src/changelog";
import { CommitType } from "../src/commits";

describe("generateChangelogEntry", () => {
  test("should generate changelog entry for a single commit", () => {
    const commits: Commit[] = [
      {
        type: CommitType.FEAT,
        message: "add new feature",
        isBreaking: false,
      },
    ];

    const entry = generateChangelogEntry("1.2.0", commits);

    expect(entry).toContain("1.2.0");
    expect(entry).toContain("add new feature");
  });

  test("should group commits by type in changelog", () => {
    const commits: Commit[] = [
      {
        type: CommitType.FEAT,
        message: "add new feature",
        isBreaking: false,
      },
      {
        type: CommitType.FIX,
        message: "fix critical bug",
        isBreaking: false,
      },
    ];

    const entry = generateChangelogEntry("1.2.0", commits);

    expect(entry).toContain("Features");
    expect(entry).toContain("Bug Fixes");
    expect(entry).toContain("add new feature");
    expect(entry).toContain("fix critical bug");
  });

  test("should include breaking changes section", () => {
    const commits: Commit[] = [
      {
        type: CommitType.FEAT,
        message: "remove old API",
        isBreaking: true,
      },
    ];

    const entry = generateChangelogEntry("2.0.0", commits);

    expect(entry).toContain("BREAKING CHANGES");
    expect(entry).toContain("remove old API");
  });

  test("should filter out docs and chore commits", () => {
    const commits: Commit[] = [
      {
        type: CommitType.FEAT,
        message: "add feature",
        isBreaking: false,
      },
      {
        type: CommitType.DOCS,
        message: "update docs",
        isBreaking: false,
      },
      {
        type: CommitType.CHORE,
        message: "update deps",
        isBreaking: false,
      },
    ];

    const entry = generateChangelogEntry("1.2.0", commits);

    expect(entry).toContain("add feature");
    expect(entry).not.toContain("update docs");
    expect(entry).not.toContain("update deps");
  });

  test("should handle commits with scopes", () => {
    const commits: Commit[] = [
      {
        type: CommitType.FEAT,
        scope: "auth",
        message: "add JWT support",
        isBreaking: false,
      },
    ];

    const entry = generateChangelogEntry("1.2.0", commits);

    expect(entry).toContain("auth");
    expect(entry).toContain("add JWT support");
  });
});
