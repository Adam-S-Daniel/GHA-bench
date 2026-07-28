import { expect, describe, it } from "bun:test";
import { generateChangelogEntry, Commit } from "./changelog";

describe("generateChangelogEntry", () => {
  it("should generate changelog entry with features and fixes", () => {
    const commits: Commit[] = [
      { hash: "abc123", message: "feat: add authentication", body: "" },
      { hash: "def456", message: "fix: resolve login bug", body: "" },
    ];

    const entry = generateChangelogEntry("1.1.0", commits);

    expect(entry).toContain("## [1.1.0]");
    expect(entry).toContain("### Features");
    expect(entry).toContain("add authentication");
    expect(entry).toContain("### Bug Fixes");
    expect(entry).toContain("resolve login bug");
  });

  it("should handle empty commit list", () => {
    const entry = generateChangelogEntry("1.0.1", []);
    expect(entry).toContain("## [1.0.1]");
  });

  it("should group commits by type", () => {
    const commits: Commit[] = [
      { hash: "a1", message: "feat: add feature 1", body: "" },
      { hash: "a2", message: "feat: add feature 2", body: "" },
      { hash: "b1", message: "fix: fix bug 1", body: "" },
    ];

    const entry = generateChangelogEntry("2.0.0", commits);

    // Features section should come before fixes
    const featIndex = entry.indexOf("### Features");
    const fixIndex = entry.indexOf("### Bug Fixes");
    expect(featIndex).toBeLessThan(fixIndex);

    // Count occurrences
    const featMatches = entry.match(/add feature/g);
    expect(featMatches?.length).toBe(2);
  });

  it("should include commit hash", () => {
    const commits: Commit[] = [
      { hash: "abc1234567890", message: "fix: important fix", body: "" },
    ];

    const entry = generateChangelogEntry("1.0.1", commits);
    expect(entry).toContain("abc1234");
  });

  it("should handle breaking changes", () => {
    const commits: Commit[] = [
      {
        hash: "xyz789",
        message: "feat!: redesign API",
        body: "BREAKING CHANGE: old endpoint removed",
      },
    ];

    const entry = generateChangelogEntry("2.0.0", commits);
    expect(entry).toContain("### Features");
    expect(entry).toContain("redesign API");
  });
});
