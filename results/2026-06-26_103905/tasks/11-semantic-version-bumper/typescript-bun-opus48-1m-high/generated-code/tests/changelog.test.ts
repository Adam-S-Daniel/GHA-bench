// TDD Cycle 3: Generate a Keep-a-Changelog style entry from parsed commits.
import { describe, expect, test } from "bun:test";
import { parseCommitLog } from "../src/commits.ts";
import { generateChangelogEntry } from "../src/changelog.ts";

describe("generateChangelogEntry", () => {
  const commits = parseCommitLog(
    "feat(auth): add OAuth login\nfix: handle empty input\nfeat!: drop v1 API\nchore: tidy",
  );

  const entry = generateChangelogEntry("2.0.0", commits, "2026-06-27");

  test("starts with a version + date header", () => {
    expect(entry).toContain("## [2.0.0] - 2026-06-27");
  });

  test("groups breaking changes under a clear heading", () => {
    expect(entry).toMatch(/### .*Breaking/i);
    expect(entry).toContain("drop v1 API");
  });

  test("lists features under a Features heading", () => {
    expect(entry).toMatch(/### Features/);
    expect(entry).toContain("**auth:** add OAuth login");
  });

  test("lists fixes under a Bug Fixes heading", () => {
    expect(entry).toMatch(/### Bug Fixes/);
    expect(entry).toContain("handle empty input");
  });

  test("omits non-release commits (chore) from the changelog body", () => {
    expect(entry).not.toContain("tidy");
  });

  test("renders a sensible message when there are no notable changes", () => {
    const empty = generateChangelogEntry("1.0.1", parseCommitLog("chore: x"), "2026-06-27");
    expect(empty).toContain("## [1.0.1] - 2026-06-27");
    expect(empty).toMatch(/no notable changes/i);
  });
});
