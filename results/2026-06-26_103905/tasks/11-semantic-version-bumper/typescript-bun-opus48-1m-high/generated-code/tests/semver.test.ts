// TDD Cycle 1: Semantic version parsing, formatting, comparison, and bumping.
// We write these expectations BEFORE the implementation exists so the suite
// starts RED, then we add the minimum code in src/semver.ts to make it GREEN.
import { describe, expect, test } from "bun:test";
import {
  parseVersion,
  formatVersion,
  bumpVersion,
  compareVersions,
  type BumpType,
  type SemanticVersion,
} from "../src/semver.ts";

describe("parseVersion", () => {
  test("parses a plain MAJOR.MINOR.PATCH string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("tolerates a leading 'v' prefix", () => {
    expect(parseVersion("v0.4.10")).toEqual({ major: 0, minor: 4, patch: 10 });
  });

  test("ignores surrounding whitespace", () => {
    expect(parseVersion("  2.0.0\n")).toEqual({ major: 2, minor: 0, patch: 0 });
  });

  test("throws a meaningful error for a non-semver string", () => {
    expect(() => parseVersion("not-a-version")).toThrow(/invalid semantic version/i);
  });

  test("throws for a partial version", () => {
    expect(() => parseVersion("1.2")).toThrow(/invalid semantic version/i);
  });
});

describe("formatVersion", () => {
  test("renders the canonical dotted form", () => {
    const v: SemanticVersion = { major: 3, minor: 1, patch: 4 };
    expect(formatVersion(v)).toBe("3.1.4");
  });
});

describe("bumpVersion", () => {
  const base: SemanticVersion = { major: 1, minor: 2, patch: 3 };

  test("major bump resets minor and patch", () => {
    expect(bumpVersion(base, "major")).toEqual({ major: 2, minor: 0, patch: 0 });
  });

  test("minor bump increments minor and resets patch", () => {
    expect(bumpVersion(base, "minor")).toEqual({ major: 1, minor: 3, patch: 0 });
  });

  test("patch bump increments only patch", () => {
    expect(bumpVersion(base, "patch")).toEqual({ major: 1, minor: 2, patch: 4 });
  });

  test("a 'none' bump returns the version unchanged", () => {
    const noBump: BumpType = "none";
    expect(bumpVersion(base, noBump)).toEqual(base);
  });
});

describe("compareVersions", () => {
  test("orders by major, then minor, then patch", () => {
    expect(compareVersions(parseVersion("1.0.0"), parseVersion("2.0.0"))).toBeLessThan(0);
    expect(compareVersions(parseVersion("1.3.0"), parseVersion("1.2.9"))).toBeGreaterThan(0);
    expect(compareVersions(parseVersion("1.2.3"), parseVersion("1.2.3"))).toBe(0);
  });
});
