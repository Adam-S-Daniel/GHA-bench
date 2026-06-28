// RED phase for the changelog generator.
//
// We produce a "Keep a Changelog"-style entry grouped by Conventional Commit
// type. The date is injected (never read from the clock) so the output is
// fully deterministic and testable.
import { describe, expect, it } from "bun:test";
import { generateChangelogEntry, prependChangelog } from "../src/changelog.ts";
import { parseCommitMessage } from "../src/commits.ts";

const COMMITS = [
  parseCommitMessage("feat(ui): add dark mode"),
  parseCommitMessage("feat: add light mode"),
  parseCommitMessage("fix(parser): handle empty input"),
  parseCommitMessage("docs: tweak readme"),
  parseCommitMessage(
    "refactor(core): rework loader\n\nBREAKING CHANGE: config now requires a version field",
  ),
];

describe("generateChangelogEntry", () => {
  const entry = generateChangelogEntry({
    version: "1.2.0",
    date: "2026-06-27",
    commits: COMMITS,
  });

  it("starts with a dated version heading", () => {
    expect(entry.split("\n")[0]).toBe("## [1.2.0] - 2026-06-27");
  });

  it("lists breaking changes first, using the footer text", () => {
    expect(entry).toContain("### ⚠ BREAKING CHANGES");
    expect(entry).toContain(
      "- **core:** config now requires a version field",
    );
    const breakingIdx = entry.indexOf("BREAKING CHANGES");
    const featuresIdx = entry.indexOf("### Features");
    expect(breakingIdx).toBeGreaterThan(-1);
    expect(featuresIdx).toBeGreaterThan(breakingIdx);
  });

  it("groups features with scope-prefixed bullets", () => {
    expect(entry).toContain("### Features");
    expect(entry).toContain("- **ui:** add dark mode");
    expect(entry).toContain("- add light mode");
  });

  it("groups bug fixes", () => {
    expect(entry).toContain("### Bug Fixes");
    expect(entry).toContain("- **parser:** handle empty input");
  });

  it("places other recognised types under Other Changes", () => {
    expect(entry).toContain("### Other Changes");
    expect(entry).toContain("- tweak readme");
  });

  it("orders sections Features before Bug Fixes before Other Changes", () => {
    const f = entry.indexOf("### Features");
    const b = entry.indexOf("### Bug Fixes");
    const o = entry.indexOf("### Other Changes");
    expect(f).toBeLessThan(b);
    expect(b).toBeLessThan(o);
  });

  it("emits a placeholder when there are no notable commits", () => {
    const empty = generateChangelogEntry({
      version: "1.0.1",
      date: "2026-06-27",
      commits: [],
    });
    expect(empty.split("\n")[0]).toBe("## [1.0.1] - 2026-06-27");
    expect(empty).toContain("_No notable changes._");
  });
});

describe("prependChangelog", () => {
  it("creates a titled changelog when none exists yet", () => {
    const entry = generateChangelogEntry({
      version: "1.0.0",
      date: "2026-06-27",
      commits: [parseCommitMessage("feat: first")],
    });
    const out = prependChangelog("", entry);
    expect(out.startsWith("# Changelog")).toBe(true);
    expect(out).toContain("## [1.0.0] - 2026-06-27");
  });

  it("inserts the newest entry above older ones but below the title", () => {
    const existing = [
      "# Changelog",
      "",
      "All notable changes to this project are documented here.",
      "",
      "## [1.0.0] - 2026-01-01",
      "",
      "### Features",
      "",
      "- old feature",
      "",
    ].join("\n");
    const newEntry = generateChangelogEntry({
      version: "1.1.0",
      date: "2026-06-27",
      commits: [parseCommitMessage("feat: new feature")],
    });
    const out = prependChangelog(existing, newEntry);

    const titleIdx = out.indexOf("# Changelog");
    const newIdx = out.indexOf("## [1.1.0]");
    const oldIdx = out.indexOf("## [1.0.0]");
    expect(titleIdx).toBeLessThan(newIdx);
    expect(newIdx).toBeLessThan(oldIdx);
  });
});
