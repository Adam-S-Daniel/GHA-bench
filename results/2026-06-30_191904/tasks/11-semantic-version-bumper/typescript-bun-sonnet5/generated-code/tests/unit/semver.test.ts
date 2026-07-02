// Unit tests for src/semver.ts — pure semantic-version parsing, formatting,
// and bumping logic. No filesystem or process access; runs directly under
// `bun test` per the TDD requirement.
import { describe, expect, test } from "bun:test";
import { bumpVersion, formatVersion, parseVersion } from "../../src/semver.ts";

describe("parseVersion", () => {
  test("parses a plain MAJOR.MINOR.PATCH string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("parses a version with a leading 'v'", () => {
    expect(parseVersion("v2.10.5")).toEqual({ major: 2, minor: 10, patch: 5 });
  });

  test("throws a descriptive error for a malformed version string", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /invalid semantic version/i,
    );
  });

  test("throws a descriptive error for an empty string", () => {
    expect(() => parseVersion("")).toThrow(/invalid semantic version/i);
  });
});

describe("formatVersion", () => {
  test("formats a Version object back into MAJOR.MINOR.PATCH", () => {
    expect(formatVersion({ major: 1, minor: 2, patch: 3 })).toBe("1.2.3");
  });
});

describe("bumpVersion", () => {
  const base = { major: 1, minor: 2, patch: 3 };

  test("'major' bump increments major and resets minor/patch to 0", () => {
    expect(bumpVersion(base, "major")).toEqual({
      major: 2,
      minor: 0,
      patch: 0,
    });
  });

  test("'minor' bump increments minor, resets patch, leaves major", () => {
    expect(bumpVersion(base, "minor")).toEqual({
      major: 1,
      minor: 3,
      patch: 0,
    });
  });

  test("'patch' bump increments only patch", () => {
    expect(bumpVersion(base, "patch")).toEqual({
      major: 1,
      minor: 2,
      patch: 4,
    });
  });

  test("'none' bump returns an equivalent, unchanged version", () => {
    expect(bumpVersion(base, "none")).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
    });
  });
});
