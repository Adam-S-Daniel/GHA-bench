// RED phase for the semver module.
//
// The semver module is the foundation: it must parse a semantic version
// string into structured components, format it back to a string, and bump
// a given component (major/minor/patch) following SemVer 2.0.0 rules.
import { describe, expect, it } from "bun:test";
import {
  bumpVersion,
  formatVersion,
  parseVersion,
  type SemVer,
} from "../src/semver.ts";

describe("parseVersion", () => {
  it("parses a plain MAJOR.MINOR.PATCH string", () => {
    expect(parseVersion("1.2.3")).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: undefined,
      build: undefined,
    });
  });

  it("tolerates a leading 'v' and surrounding whitespace", () => {
    expect(parseVersion("  v0.0.1\n")).toEqual({
      major: 0,
      minor: 0,
      patch: 1,
      prerelease: undefined,
      build: undefined,
    });
  });

  it("captures prerelease and build metadata", () => {
    expect(parseVersion("1.2.3-rc.1+build.5")).toEqual({
      major: 1,
      minor: 2,
      patch: 3,
      prerelease: "rc.1",
      build: "build.5",
    });
  });

  it("throws a meaningful error on a non-semver string", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /invalid semantic version/i,
    );
  });

  it("throws on an empty string", () => {
    expect(() => parseVersion("   ")).toThrow(/invalid semantic version/i);
  });
});

describe("formatVersion", () => {
  it("renders core components", () => {
    const v: SemVer = { major: 2, minor: 0, patch: 9 };
    expect(formatVersion(v)).toBe("2.0.9");
  });

  it("re-appends prerelease and build when present", () => {
    const v: SemVer = {
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: "beta.2",
      build: "exp.sha.5114f85",
    };
    expect(formatVersion(v)).toBe("1.4.0-beta.2+exp.sha.5114f85");
  });

  it("round-trips through parseVersion", () => {
    expect(formatVersion(parseVersion("10.20.30"))).toBe("10.20.30");
  });
});

describe("bumpVersion", () => {
  it("bumps major and resets minor/patch/prerelease/build", () => {
    expect(formatVersion(bumpVersion(parseVersion("1.2.3-rc.1"), "major"))).toBe(
      "2.0.0",
    );
  });

  it("bumps minor and resets patch", () => {
    expect(formatVersion(bumpVersion(parseVersion("1.2.3"), "minor"))).toBe(
      "1.3.0",
    );
  });

  it("bumps patch", () => {
    expect(formatVersion(bumpVersion(parseVersion("1.2.3"), "patch"))).toBe(
      "1.2.4",
    );
  });

  it("leaves the version unchanged for a 'none' bump", () => {
    expect(formatVersion(bumpVersion(parseVersion("1.2.3"), "none"))).toBe(
      "1.2.3",
    );
  });
});
