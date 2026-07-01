// Unit tests for src/changelog.ts — rendering a Keep-a-Changelog-style entry
// from a version, a date, and the commits that produced it.
import { describe, expect, test } from "bun:test";
import { generateChangelogEntry } from "../../src/changelog.ts";
import type { Commit } from "../../src/commits.ts";

describe("generateChangelogEntry", () => {
  test("groups commits into Breaking Changes, Features, and Fixes sections", () => {
    const commits: Commit[] = [
      { hash: "aaa1111", subject: "feat(auth): add OAuth login", body: "" },
      {
        hash: "bbb2222",
        subject: "fix(parser): handle trailing commas",
        body: "",
      },
      {
        hash: "ccc3333",
        subject: "feat(api)!: redesign response envelope",
        body: "",
      },
      { hash: "ddd4444", subject: "docs: fix typo in README", body: "" },
    ];

    const entry = generateChangelogEntry("2.0.0", "2026-01-05", commits);

    expect(entry).toBe(
      `## [2.0.0] - 2026-01-05

### Breaking Changes

- api: redesign response envelope (ccc3333)

### Features

- auth: add OAuth login (aaa1111)

### Fixes

- parser: handle trailing commas (bbb2222)
`,
    );
  });

  test("omits empty sections entirely", () => {
    const commits: Commit[] = [
      { hash: "aaa1111", subject: "fix: correct rounding error", body: "" },
    ];

    const entry = generateChangelogEntry("1.0.1", "2026-01-05", commits);

    expect(entry).toBe(
      `## [1.0.1] - 2026-01-05

### Fixes

- correct rounding error (aaa1111)
`,
    );
    expect(entry).not.toContain("Breaking Changes");
    expect(entry).not.toContain("Features");
  });

  test("falls back to a 'No notable changes' line when nothing is conventional", () => {
    const commits: Commit[] = [
      { hash: "aaa1111", subject: "chore: bump lockfile", body: "" },
    ];

    const entry = generateChangelogEntry("1.0.0", "2026-01-05", commits);

    expect(entry).toBe(
      `## [1.0.0] - 2026-01-05

No notable changes.
`,
    );
  });
});
