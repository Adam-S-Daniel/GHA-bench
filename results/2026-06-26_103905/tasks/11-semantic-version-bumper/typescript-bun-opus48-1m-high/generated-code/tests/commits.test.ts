// TDD Cycle 2: Parsing conventional commit messages and reducing a list of
// commits down to a single bump decision (the highest precedence wins).
import { describe, expect, test } from "bun:test";
import {
  parseCommit,
  parseCommitLog,
  determineBump,
  type ParsedCommit,
} from "../src/commits.ts";

describe("parseCommit", () => {
  test("parses a feat commit -> minor", () => {
    const c = parseCommit("feat: add login page");
    expect(c.type).toBe("feat");
    expect(c.scope).toBeNull();
    expect(c.description).toBe("add login page");
    expect(c.breaking).toBe(false);
    expect(c.bump).toBe("minor");
  });

  test("parses a fix commit -> patch", () => {
    const c = parseCommit("fix: correct null pointer");
    expect(c.type).toBe("fix");
    expect(c.bump).toBe("patch");
  });

  test("captures an optional scope", () => {
    const c = parseCommit("feat(auth): support OAuth");
    expect(c.type).toBe("feat");
    expect(c.scope).toBe("auth");
    expect(c.description).toBe("support OAuth");
  });

  test("treats a trailing '!' as a breaking change -> major", () => {
    const c = parseCommit("feat!: drop node 16 support");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  test("'!' works together with a scope", () => {
    const c = parseCommit("refactor(core)!: rewrite scheduler");
    expect(c.scope).toBe("core");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  test("a 'BREAKING CHANGE:' footer forces a major bump", () => {
    const c = parseCommit("feat: new API\n\nBREAKING CHANGE: removes the old endpoint");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  test("non-release types (chore, docs, etc.) -> none", () => {
    expect(parseCommit("chore: tidy up").bump).toBe("none");
    expect(parseCommit("docs: update readme").bump).toBe("none");
  });

  test("a non-conventional message -> none, type 'other'", () => {
    const c = parseCommit("just a random commit");
    expect(c.type).toBe("other");
    expect(c.bump).toBe("none");
    expect(c.description).toBe("just a random commit");
  });
});

describe("parseCommitLog", () => {
  test("splits a newline-delimited log, ignoring blank lines", () => {
    const log = "feat: a\nfix: b\n\nchore: c\n";
    const commits = parseCommitLog(log);
    expect(commits.map((c: ParsedCommit) => c.type)).toEqual(["feat", "fix", "chore"]);
  });

  test("supports an explicit NUL-style record separator for multi-line bodies", () => {
    // Records separated by a line containing only '---' so commit bodies
    // (which themselves contain newlines) are preserved intact.
    const log = "feat: one\n\nbody line\n---\nfix: two";
    const commits = parseCommitLog(log);
    expect(commits.length).toBe(2);
    expect(commits[0]!.type).toBe("feat");
    expect(commits[1]!.type).toBe("fix");
  });
});

describe("determineBump", () => {
  test("returns the highest precedence bump across commits", () => {
    expect(determineBump(parseCommitLog("fix: a\nfeat: b"))).toBe("minor");
    expect(determineBump(parseCommitLog("fix: a\nfix: b"))).toBe("patch");
    expect(determineBump(parseCommitLog("feat: a\nfeat!: b"))).toBe("major");
  });

  test("returns 'none' when nothing is release-worthy", () => {
    expect(determineBump(parseCommitLog("chore: a\ndocs: b"))).toBe("none");
  });

  test("returns 'none' for an empty list", () => {
    expect(determineBump([])).toBe("none");
  });
});
