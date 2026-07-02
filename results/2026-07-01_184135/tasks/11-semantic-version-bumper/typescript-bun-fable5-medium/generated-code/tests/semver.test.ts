// TDD cycle 1 (RED): semver parsing and bumping.
// These tests were written BEFORE src/semver.ts existed.
import { describe, expect, test } from "bun:test";
import { parseSemver, formatSemver, bumpVersion } from "../src/semver";

describe("parseSemver", () => {
  test("parses a valid semver string into its numeric parts", () => {
    expect(parseSemver("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("tolerates a leading 'v' prefix", () => {
    expect(parseSemver("v10.20.30")).toEqual({ major: 10, minor: 20, patch: 30 });
  });

  test("throws a meaningful error on garbage input", () => {
    expect(() => parseSemver("not-a-version")).toThrow(
      /Invalid semantic version: "not-a-version"/,
    );
  });

  test("throws on incomplete versions like '1.2'", () => {
    expect(() => parseSemver("1.2")).toThrow(/Invalid semantic version/);
  });
});

describe("formatSemver", () => {
  test("renders parts back into a dotted string", () => {
    expect(formatSemver({ major: 2, minor: 0, patch: 1 })).toBe("2.0.1");
  });
});

describe("bumpVersion", () => {
  test("major bump resets minor and patch", () => {
    expect(bumpVersion("1.2.3", "major")).toBe("2.0.0");
  });

  test("minor bump resets patch", () => {
    expect(bumpVersion("1.2.3", "minor")).toBe("1.3.0");
  });

  test("patch bump increments patch only", () => {
    expect(bumpVersion("1.2.3", "patch")).toBe("1.2.4");
  });
});
