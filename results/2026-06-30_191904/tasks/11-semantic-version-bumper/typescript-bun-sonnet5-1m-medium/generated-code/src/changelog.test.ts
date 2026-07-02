import { describe, expect, test } from "bun:test";
import { parseCommitLog, generateChangelogEntry } from "./changelog";

// RED: changelog.ts does not exist yet.

describe("parseCommitLog", () => {
  test("splits a commit log fixture into trimmed, non-empty lines", () => {
    const raw = "feat: add login page\n\nfix: correct typo\n  \nchore: tidy\n";
    expect(parseCommitLog(raw)).toEqual([
      "feat: add login page",
      "fix: correct typo",
      "chore: tidy",
    ]);
  });

  test("ignores lines starting with '#' as comments", () => {
    const raw = "# mock commit log\nfeat: add feature\n# another comment";
    expect(parseCommitLog(raw)).toEqual(["feat: add feature"]);
  });
});

describe("generateChangelogEntry", () => {
  test("groups commits by conventional type under a version heading", () => {
    const entry = generateChangelogEntry({
      version: "1.1.0",
      date: "2026-07-01",
      commits: [
        "feat: add login page",
        "fix: correct off-by-one error",
        "chore: update deps",
      ],
    });

    expect(entry).toBe(
      [
        "## 1.1.0 (2026-07-01)",
        "",
        "### Features",
        "- add login page",
        "",
        "### Fixes",
        "- correct off-by-one error",
        "",
        "### Other",
        "- update deps",
        "",
      ].join("\n"),
    );
  });

  test("notes when there are no user-facing changes", () => {
    const entry = generateChangelogEntry({
      version: "1.0.0",
      date: "2026-07-01",
      commits: ["chore: update deps"],
    });

    expect(entry).toBe(
      [
        "## 1.0.0 (2026-07-01)",
        "",
        "### Other",
        "- update deps",
        "",
      ].join("\n"),
    );
  });
});
