/**
 * RED phase (cycle 3): tests for changelog entry generation.
 * Written BEFORE src/changelog.ts exists.
 */
import { describe, expect, test } from "bun:test";
import { renderChangelogEntry, prependChangelogEntry } from "../src/changelog";
import { parseCommit } from "../src/commits";

const COMMITS = [
  parseCommit("feat(api): add pagination"),
  parseCommit("fix: handle empty input"),
  parseCommit("feat!: drop legacy config"),
  parseCommit("Update README"),
];

describe("renderChangelogEntry", () => {
  test("groups commits under Breaking/Features/Fixes/Other headings", () => {
    const entry = renderChangelogEntry("2.0.0", COMMITS, "2026-07-02");
    expect(entry).toContain("## 2.0.0 (2026-07-02)");
    expect(entry).toContain("### Breaking Changes\n\n- drop legacy config");
    expect(entry).toContain("### Features\n\n- **api**: add pagination");
    expect(entry).toContain("### Fixes\n\n- handle empty input");
    expect(entry).toContain("### Other\n\n- Update README");
  });

  test("omits empty sections", () => {
    const entry = renderChangelogEntry(
      "1.0.1",
      [parseCommit("fix: oops")],
      "2026-07-02",
    );
    expect(entry).toContain("### Fixes");
    expect(entry).not.toContain("### Features");
    expect(entry).not.toContain("### Breaking Changes");
    expect(entry).not.toContain("### Other");
  });
});

describe("prependChangelogEntry", () => {
  test("starts a fresh changelog with a title", () => {
    const out = prependChangelogEntry("", "## 1.1.0 (2026-07-02)\n\nbody\n");
    expect(out.startsWith("# Changelog\n")).toBe(true);
    expect(out).toContain("## 1.1.0 (2026-07-02)");
  });

  test("inserts the new entry above existing entries, keeping the title", () => {
    const existing = "# Changelog\n\n## 1.0.0 (2026-01-01)\n\n- old stuff\n";
    const out = prependChangelogEntry(existing, "## 1.1.0 (2026-07-02)\n\n- new\n");
    const idxNew = out.indexOf("## 1.1.0");
    const idxOld = out.indexOf("## 1.0.0");
    expect(out.startsWith("# Changelog\n")).toBe(true);
    expect(idxNew).toBeGreaterThan(-1);
    expect(idxOld).toBeGreaterThan(idxNew);
  });
});
