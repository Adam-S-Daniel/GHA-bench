// Unit tests for src/commits.ts — parsing `git log` style commit logs and
// deriving a semver bump type from Conventional Commits
// (https://www.conventionalcommits.org/) headers.
import { describe, expect, test } from "bun:test";
import { determineBumpType, parseCommitLog } from "../../src/commits.ts";

// A realistic `git log` (default format) excerpt: each commit starts with
// "commit <sha>", followed by Author/Date lines, a blank line, then the
// message indented 4 spaces (subject line, optionally a blank line, then
// body paragraphs — exactly what `git log` without --format produces).
const SAMPLE_LOG = `commit 3a7c1e9f8b2d4a6c9e1f3b5d7a9c1e3f5b7d9a1c
Author: Ada Lovelace <ada@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    feat(auth): add OAuth login support

    Adds Google and GitHub OAuth providers.

commit 1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4
Author: Grace Hopper <grace@example.com>
Date:   Mon Jan 5 09:30:00 2026 +0000

    fix(parser): handle trailing commas correctly

commit 0f1e2d3c4b5a69788796a5b4c3d2e1f0a9b8c7d6
Author: Ada Lovelace <ada@example.com>
Date:   Mon Jan 5 09:00:00 2026 +0000

    docs: fix typo in README
`;

describe("parseCommitLog", () => {
  test("parses each commit's hash, subject, and body", () => {
    const commits = parseCommitLog(SAMPLE_LOG);
    expect(commits).toHaveLength(3);
    expect(commits[0]).toEqual({
      hash: "3a7c1e9f8b2d4a6c9e1f3b5d7a9c1e3f5b7d9a1c",
      subject: "feat(auth): add OAuth login support",
      body: "Adds Google and GitHub OAuth providers.",
    });
    expect(commits[1]).toEqual({
      hash: "1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4",
      subject: "fix(parser): handle trailing commas correctly",
      body: "",
    });
  });

  test("returns an empty array for an empty log", () => {
    expect(parseCommitLog("")).toEqual([]);
  });

  test("throws a descriptive error when given a log with no 'commit' headers", () => {
    expect(() => parseCommitLog("not a git log at all")).toThrow(
      /no commits found/i,
    );
  });
});

describe("determineBumpType", () => {
  test("'fix:' commit alone triggers a patch bump", () => {
    const commits = parseCommitLog(SAMPLE_LOG); // feat + fix + docs
    // isolate just the fix+docs commits to test patch-only precedence
    expect(determineBumpType([commits[1]!, commits[2]!])).toBe("patch");
  });

  test("'feat:' commit triggers a minor bump", () => {
    const commits = parseCommitLog(SAMPLE_LOG);
    expect(determineBumpType([commits[0]!, commits[2]!])).toBe("minor");
  });

  test("a commit with '!' after the type/scope triggers a major bump", () => {
    const commits = parseCommitLog(
      `commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    feat(api)!: redesign response envelope
`,
    );
    expect(determineBumpType(commits)).toBe("major");
  });

  test("a 'BREAKING CHANGE:' footer in the body triggers a major bump", () => {
    const commits = parseCommitLog(
      `commit bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    fix: correct rounding error

    BREAKING CHANGE: rounding now truncates instead of rounds
`,
    );
    expect(determineBumpType(commits)).toBe("major");
  });

  test("major takes precedence over minor and patch when mixed", () => {
    const commits = parseCommitLog(SAMPLE_LOG).concat(
      parseCommitLog(
        `commit cccccccccccccccccccccccccccccccccccccccc
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    feat!: drop support for Node 16
`,
      ),
    );
    expect(determineBumpType(commits)).toBe("major");
  });

  test("commits with no conventional prefix yield 'none'", () => {
    const commits = parseCommitLog(
      `commit dddddddddddddddddddddddddddddddddddddddd
Author: A <a@example.com>
Date:   Mon Jan 5 10:00:00 2026 +0000

    docs: fix typo in README
`,
    );
    expect(determineBumpType(commits)).toBe("none");
  });

  test("an empty commit list yields 'none'", () => {
    expect(determineBumpType([])).toBe("none");
  });
});
