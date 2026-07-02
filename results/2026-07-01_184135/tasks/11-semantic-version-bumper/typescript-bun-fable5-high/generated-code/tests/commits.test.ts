/**
 * RED phase (cycle 2): tests for conventional-commit parsing and bump
 * determination. Written BEFORE src/commits.ts exists.
 *
 * Rules under test: breaking change -> major, feat -> minor, fix -> patch,
 * anything else -> none. Breaking is signalled by a "!" after the type/scope
 * or a "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer.
 */
import { describe, expect, test } from "bun:test";
import { parseCommit, determineBump } from "../src/commits";

describe("parseCommit", () => {
  test("parses type, scope, and description", () => {
    expect(parseCommit("feat(api): add pagination")).toEqual({
      type: "feat",
      scope: "api",
      description: "add pagination",
      breaking: false,
      raw: "feat(api): add pagination",
    });
  });

  test("parses a scopeless commit", () => {
    const c = parseCommit("fix: handle empty input");
    expect(c.type).toBe("fix");
    expect(c.scope).toBeNull();
    expect(c.description).toBe("handle empty input");
  });

  test("detects breaking via '!' marker", () => {
    expect(parseCommit("feat!: drop node 14 support").breaking).toBe(true);
    expect(parseCommit("refactor(core)!: rewrite scheduler").breaking).toBe(true);
  });

  test("detects breaking via BREAKING CHANGE footer", () => {
    const msg = "feat: new config format\n\nBREAKING CHANGE: old configs no longer load";
    expect(parseCommit(msg).breaking).toBe(true);
  });

  test("detects breaking via BREAKING-CHANGE footer", () => {
    const msg = "fix: tweak\n\nBREAKING-CHANGE: behaviour differs";
    expect(parseCommit(msg).breaking).toBe(true);
  });

  test("treats non-conventional messages as type 'other'", () => {
    const c = parseCommit("Update README");
    expect(c.type).toBe("other");
    expect(c.description).toBe("Update README");
    expect(c.breaking).toBe(false);
  });
});

describe("determineBump", () => {
  test("breaking change wins over everything -> major", () => {
    expect(
      determineBump([
        parseCommit("fix: small thing"),
        parseCommit("feat!: breaking feature"),
        parseCommit("feat: nice feature"),
      ]),
    ).toBe("major");
  });

  test("feat without breaking -> minor", () => {
    expect(
      determineBump([parseCommit("fix: a"), parseCommit("feat: b")]),
    ).toBe("minor");
  });

  test("fix only -> patch", () => {
    expect(
      determineBump([parseCommit("fix: a"), parseCommit("docs: b")]),
    ).toBe("patch");
  });

  test("no releasable commits -> none", () => {
    expect(
      determineBump([parseCommit("docs: readme"), parseCommit("chore: deps")]),
    ).toBe("none");
  });

  test("empty commit list -> none", () => {
    expect(determineBump([])).toBe("none");
  });
});
