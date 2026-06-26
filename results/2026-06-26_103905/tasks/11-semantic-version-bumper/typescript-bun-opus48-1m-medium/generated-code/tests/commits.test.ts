// TDD step 2 (RED): parse conventional commit messages and derive the bump.
import { describe, expect, test } from "bun:test";
import {
  parseCommits,
  determineBump,
  type Commit,
} from "../src/commits";

describe("parseCommits", () => {
  test("parses type, scope, subject and breaking flag from a log", () => {
    const log = [
      "feat(api): add pagination",
      "fix: correct off-by-one",
      "chore: tidy up",
    ].join("\n");

    const commits = parseCommits(log);
    expect(commits).toEqual([
      { type: "feat", scope: "api", subject: "add pagination", breaking: false },
      { type: "fix", scope: null, subject: "correct off-by-one", breaking: false },
      { type: "chore", scope: null, subject: "tidy up", breaking: false },
    ]);
  });

  test("detects breaking change via '!' marker", () => {
    const commits = parseCommits("feat!: drop node 16 support");
    expect(commits[0]?.breaking).toBe(true);
  });

  test("ignores blank lines", () => {
    const commits = parseCommits("\n\nfix: a\n\n");
    expect(commits).toHaveLength(1);
  });

  test("treats non-conventional lines as type 'other'", () => {
    const commits = parseCommits("just some message");
    expect(commits[0]).toEqual({
      type: "other",
      scope: null,
      subject: "just some message",
      breaking: false,
    });
  });
});

describe("determineBump", () => {
  const mk = (overrides: Partial<Commit>): Commit => ({
    type: "other",
    scope: null,
    subject: "",
    breaking: false,
    ...overrides,
  });

  test("any breaking change yields a major bump", () => {
    expect(
      determineBump([mk({ type: "fix" }), mk({ type: "feat", breaking: true })]),
    ).toBe("major");
  });

  test("a feat yields a minor bump", () => {
    expect(determineBump([mk({ type: "fix" }), mk({ type: "feat" })])).toBe(
      "minor",
    );
  });

  test("only fixes yield a patch bump", () => {
    expect(determineBump([mk({ type: "fix" }), mk({ type: "chore" })])).toBe(
      "patch",
    );
  });

  test("no relevant commits yields null (no release)", () => {
    expect(determineBump([mk({ type: "chore" }), mk({ type: "docs" })])).toBe(
      null,
    );
  });

  test("empty commit list yields null", () => {
    expect(determineBump([])).toBe(null);
  });
});
