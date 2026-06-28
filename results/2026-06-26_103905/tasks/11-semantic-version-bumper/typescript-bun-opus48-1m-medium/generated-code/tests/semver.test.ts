// TDD step 1 (RED): semantic version parsing, formatting and bumping.
// We write these expectations BEFORE the implementation exists.
import { describe, expect, test } from "bun:test";
import {
  parseVersion,
  formatVersion,
  bumpVersion,
  type SemVer,
} from "../src/semver";

describe("parseVersion", () => {
  test("parses a plain semantic version string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("tolerates a leading 'v' prefix", () => {
    expect(parseVersion("v0.4.10")).toEqual({ major: 0, minor: 4, patch: 10 });
  });

  test("throws a meaningful error on garbage input", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /invalid semantic version/i,
    );
  });
});

describe("formatVersion", () => {
  test("renders a SemVer back to a dotted string", () => {
    const v: SemVer = { major: 2, minor: 0, patch: 1 };
    expect(formatVersion(v)).toBe("2.0.1");
  });
});

describe("bumpVersion", () => {
  test("major bump resets minor and patch", () => {
    expect(bumpVersion({ major: 1, minor: 4, patch: 2 }, "major")).toEqual({
      major: 2,
      minor: 0,
      patch: 0,
    });
  });

  test("minor bump resets patch", () => {
    expect(bumpVersion({ major: 1, minor: 4, patch: 2 }, "minor")).toEqual({
      major: 1,
      minor: 5,
      patch: 0,
    });
  });

  test("patch bump increments patch only", () => {
    expect(bumpVersion({ major: 1, minor: 4, patch: 2 }, "patch")).toEqual({
      major: 1,
      minor: 4,
      patch: 3,
    });
  });
});
