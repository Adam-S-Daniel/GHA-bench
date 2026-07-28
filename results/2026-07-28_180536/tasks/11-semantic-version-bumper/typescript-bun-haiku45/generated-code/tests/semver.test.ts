// TDD: Write failing test first, then implement minimum code to make it pass.

import { expect, test, describe } from "bun:test";
import { parseVersion, bumpVersion, VersionBump } from "../src/semver";

describe("parseVersion", () => {
  test("should parse a semantic version string correctly", () => {
    const version = parseVersion("1.2.3");
    expect(version).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
    });
  });

  test("should parse version with leading v", () => {
    const version = parseVersion("v1.2.3");
    expect(version).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
    });
  });

  test("should throw error for invalid version format", () => {
    expect(() => parseVersion("invalid")).toThrow();
  });
});

describe("bumpVersion", () => {
  test("should bump patch version for fix commits", () => {
    const bumped = bumpVersion("1.2.3", VersionBump.PATCH);
    expect(bumped).toBe("1.2.4");
  });

  test("should bump minor version for feature commits", () => {
    const bumped = bumpVersion("1.2.3", VersionBump.MINOR);
    expect(bumped).toBe("1.3.0");
  });

  test("should bump major version for breaking changes", () => {
    const bumped = bumpVersion("1.2.3", VersionBump.MAJOR);
    expect(bumped).toBe("2.0.0");
  });

  test("should handle version 0.0.0", () => {
    const bumped = bumpVersion("0.0.0", VersionBump.MAJOR);
    expect(bumped).toBe("1.0.0");
  });
});
