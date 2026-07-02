// TDD cycle 2 (RED): conventional-commit parsing and bump determination.
// Written before src/commits.ts existed. Uses the mock commit-log fixtures
// in fixtures/ so the same inputs drive unit tests and the CI pipeline.
import { describe, expect, test } from "bun:test";
import { parseCommits, determineBumpType } from "../src/commits";

const read = (name: string): Promise<string> =>
  Bun.file(new URL(`../fixtures/${name}`, import.meta.url)).text();

describe("parseCommits", () => {
  test("parses type, scope, breaking flag and description", () => {
    const [c] = parseCommits("feat(auth): add OAuth2 login flow");
    expect(c).toEqual({
      type: "feat",
      scope: "auth",
      breaking: false,
      description: "add OAuth2 login flow",
      raw: "feat(auth): add OAuth2 login flow",
    });
  });

  test("marks '!' commits as breaking", () => {
    const [c] = parseCommits("feat(api)!: remove deprecated v1 endpoints");
    expect(c.breaking).toBe(true);
  });

  test("detects 'BREAKING CHANGE:' footers", () => {
    const [c] = parseCommits(
      "fix: rework config\n\nBREAKING CHANGE: config file format changed",
    );
    expect(c.breaking).toBe(true);
  });

  test("treats non-conventional messages as type 'other'", () => {
    const [c] = parseCommits("random message with no prefix");
    expect(c.type).toBe("other");
    expect(c.description).toBe("random message with no prefix");
  });

  test("skips blank lines between one-line commit subjects", () => {
    expect(parseCommits("feat: a\nfix: b\n\n")).toHaveLength(2);
  });
});

describe("determineBumpType", () => {
  test("feat commits produce a minor bump", async () => {
    expect(determineBumpType(parseCommits(await read("commits-feat.txt")))).toBe("minor");
  });

  test("fix commits produce a patch bump", async () => {
    expect(determineBumpType(parseCommits(await read("commits-fix.txt")))).toBe("patch");
  });

  test("breaking commits win over feat/fix and produce a major bump", async () => {
    expect(determineBumpType(parseCommits(await read("commits-breaking.txt")))).toBe("major");
  });

  test("chore/docs-only history produces no bump", async () => {
    expect(determineBumpType(parseCommits(await read("commits-none.txt")))).toBeNull();
  });
});
