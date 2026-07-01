// TDD cycle 3 (RED): changelog entry generation, written before src/changelog.ts.
import { describe, expect, test } from "bun:test";
import { generateChangelogEntry, prependChangelog } from "../src/changelog";
import { parseCommits } from "../src/commits";

const COMMITS = parseCommits(
  [
    "feat(api)!: remove deprecated v1 endpoints",
    "feat(ui): add dark mode toggle",
    "fix(core): correct off-by-one in pagination",
    "chore: bump deps",
  ].join("\n"),
);

describe("generateChangelogEntry", () => {
  const entry = generateChangelogEntry("2.0.0", COMMITS, "2026-07-01");

  test("starts with a versioned, dated heading", () => {
    expect(entry.startsWith("## 2.0.0 (2026-07-01)")).toBe(true);
  });

  test("groups commits under Breaking/Features/Fixes sections", () => {
    expect(entry).toContain("### Breaking Changes\n\n- **api**: remove deprecated v1 endpoints");
    expect(entry).toContain("### Features\n\n- **ui**: add dark mode toggle");
    expect(entry).toContain("### Fixes\n\n- **core**: correct off-by-one in pagination");
  });

  test("omits chore/docs commits and empty sections", () => {
    expect(entry).not.toContain("bump deps");
    const noFixes = generateChangelogEntry("1.1.0", parseCommits("feat: a"), "2026-07-01");
    expect(noFixes).not.toContain("### Fixes");
  });

  test("renders unscoped commits without a bold scope prefix", () => {
    const e = generateChangelogEntry("1.1.0", parseCommits("feat: plain"), "2026-07-01");
    expect(e).toContain("- plain");
  });
});

describe("prependChangelog", () => {
  test("inserts the new entry after the '# Changelog' title of an existing file", () => {
    const existing = "# Changelog\n\n## 1.0.0 (2026-01-01)\n\n### Features\n\n- old\n";
    const result = prependChangelog(existing, "## 1.1.0 (2026-07-01)\n\n### Features\n\n- new\n");
    expect(result.indexOf("## 1.1.0")).toBeGreaterThan(result.indexOf("# Changelog"));
    expect(result.indexOf("## 1.1.0")).toBeLessThan(result.indexOf("## 1.0.0"));
  });

  test("creates the title when the file was empty", () => {
    const result = prependChangelog("", "## 1.0.1 (2026-07-01)\n\n### Fixes\n\n- x\n");
    expect(result.startsWith("# Changelog\n")).toBe(true);
    expect(result).toContain("## 1.0.1");
  });
});
