/**
 * RED phase (cycle 5): tests for reading mock commit-log fixtures.
 *
 * Fixture format: full commit messages (subject + optional body) separated by
 * a line containing exactly "====COMMIT====" — mirrors what
 * `git log --format=%B%n====COMMIT====` would produce.
 */
import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { parseCommitLog, readCommitLogFile } from "../src/commitLog";

const FIXTURES = join(import.meta.dir, "..", "fixtures");

describe("parseCommitLog", () => {
  test("splits messages on the delimiter line", () => {
    const commits = parseCommitLog(
      "feat: a\n====COMMIT====\nfix: b\n====COMMIT====\ndocs: c\n",
    );
    expect(commits.map((c) => c.type)).toEqual(["feat", "fix", "docs"]);
  });

  test("keeps multi-line bodies with a single commit intact", () => {
    const commits = parseCommitLog(
      "feat: x\n\nBREAKING CHANGE: gone\n====COMMIT====\nfix: y\n",
    );
    expect(commits[0]?.breaking).toBe(true);
    expect(commits[1]?.type).toBe("fix");
  });

  test("ignores empty segments (trailing delimiter, blank log)", () => {
    expect(parseCommitLog("feat: a\n====COMMIT====\n")).toHaveLength(1);
    expect(parseCommitLog("")).toHaveLength(0);
  });
});

describe("readCommitLogFile", () => {
  test("reads the breaking fixture and finds the breaking commit", () => {
    const commits = readCommitLogFile(join(FIXTURES, "commits-breaking.log"));
    expect(commits).toHaveLength(3);
    expect(commits.some((c) => c.breaking)).toBe(true);
  });

  test("throws meaningfully when the log file is missing", () => {
    expect(() => readCommitLogFile(join(FIXTURES, "nope.log"))).toThrow(
      /Commit log file not found/,
    );
  });
});
