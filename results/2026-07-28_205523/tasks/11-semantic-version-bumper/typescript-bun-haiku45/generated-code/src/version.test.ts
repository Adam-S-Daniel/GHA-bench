import { expect, describe, it } from "bun:test";
import { parseVersion, bumpVersion, BumpType, versionToString } from "./version";

describe("parseVersion", () => {
  it("should parse a valid semantic version string", () => {
    const result = parseVersion("1.2.3");
    expect(result).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  it("should parse version from package.json format", () => {
    const result = parseVersion("2.0.5");
    expect(result).toEqual({ major: 2, minor: 0, patch: 5 });
  });

  it("should throw on invalid version format", () => {
    expect(() => parseVersion("invalid")).toThrow();
  });

  it("should handle versions with leading v", () => {
    const result = parseVersion("v1.2.3");
    expect(result).toEqual({ major: 1, minor: 2, patch: 3 });
  });
});

describe("bumpVersion", () => {
  it("should bump patch version for a fix", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const result = bumpVersion(current, "patch");
    expect(result).toEqual({ major: 1, minor: 2, patch: 4 });
  });

  it("should bump minor version and reset patch for a feature", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const result = bumpVersion(current, "minor");
    expect(result).toEqual({ major: 1, minor: 3, patch: 0 });
  });

  it("should bump major version and reset minor/patch for breaking change", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const result = bumpVersion(current, "major");
    expect(result).toEqual({ major: 2, minor: 0, patch: 0 });
  });
});

describe("versionToString", () => {
  it("should convert version object to string", () => {
    const version = { major: 1, minor: 2, patch: 3 };
    expect(versionToString(version)).toBe("1.2.3");
  });
});
