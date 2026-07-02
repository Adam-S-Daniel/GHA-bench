/**
 * RED phase (cycle 1): tests for semantic version parsing/formatting/bumping.
 * Written BEFORE src/semver.ts exists — `bun test` must fail first.
 */
import { describe, expect, test } from "bun:test";
import { parseVersion, formatVersion, bumpVersion } from "../src/semver";

describe("parseVersion", () => {
  test("parses a plain semver string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("tolerates a leading 'v' prefix", () => {
    expect(parseVersion("v10.0.42")).toEqual({ major: 10, minor: 0, patch: 42 });
  });

  test("tolerates surrounding whitespace", () => {
    expect(parseVersion("  2.0.1\n")).toEqual({ major: 2, minor: 0, patch: 1 });
  });

  test("throws a meaningful error on garbage input", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /Invalid semantic version: "not-a-version"/,
    );
  });

  test("throws on incomplete versions", () => {
    expect(() => parseVersion("1.2")).toThrow(/Invalid semantic version/);
  });
});

describe("formatVersion", () => {
  test("renders a SemVer object back to a string", () => {
    expect(formatVersion({ major: 1, minor: 2, patch: 3 })).toBe("1.2.3");
  });
});

describe("bumpVersion", () => {
  test("major bump resets minor and patch", () => {
    expect(bumpVersion({ major: 1, minor: 4, patch: 9 }, "major")).toEqual({
      major: 2,
      minor: 0,
      patch: 0,
    });
  });

  test("minor bump resets patch", () => {
    expect(bumpVersion({ major: 1, minor: 1, patch: 7 }, "minor")).toEqual({
      major: 1,
      minor: 2,
      patch: 0,
    });
  });

  test("patch bump increments patch only", () => {
    expect(bumpVersion({ major: 1, minor: 1, patch: 7 }, "patch")).toEqual({
      major: 1,
      minor: 1,
      patch: 8,
    });
  });

  test("'none' bump leaves the version untouched", () => {
    expect(bumpVersion({ major: 3, minor: 2, patch: 1 }, "none")).toEqual({
      major: 3,
      minor: 2,
      patch: 1,
    });
  });
});
