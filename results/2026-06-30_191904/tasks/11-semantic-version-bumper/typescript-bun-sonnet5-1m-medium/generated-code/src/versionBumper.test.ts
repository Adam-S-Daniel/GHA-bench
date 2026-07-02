import { describe, expect, test } from "bun:test";
import { parseVersion, determineBumpType, bumpVersion } from "./versionBumper";

// RED: these imports will fail to compile/run until versionBumper.ts exists.

describe("parseVersion", () => {
  test("parses a well-formed semantic version string", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("throws a meaningful error on malformed input", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /invalid semantic version/i,
    );
  });
});

describe("determineBumpType", () => {
  test("returns 'minor' when a feat commit is present", () => {
    expect(
      determineBumpType(["feat: add login page", "chore: tidy up"]),
    ).toBe("minor");
  });

  test("returns 'patch' when only fix commits are present", () => {
    expect(determineBumpType(["fix: correct off-by-one error"])).toBe(
      "patch",
    );
  });

  test("returns 'major' when a breaking change marker is present", () => {
    expect(
      determineBumpType(["feat!: remove legacy endpoint", "fix: minor bug"]),
    ).toBe("major");
  });

  test("returns 'major' when a BREAKING CHANGE footer is present", () => {
    expect(
      determineBumpType([
        "feat: new reporting engine",
        "BREAKING CHANGE: removes the old reporting API",
      ]),
    ).toBe("major");
  });

  test("returns 'none' when no commits affect versioning", () => {
    expect(determineBumpType(["chore: update deps", "docs: fix typo"])).toBe(
      "none",
    );
  });

  test("minor takes precedence over patch", () => {
    expect(
      determineBumpType(["fix: patch a bug", "feat: add a feature"]),
    ).toBe("minor");
  });
});

describe("bumpVersion", () => {
  test("bumps the major version and resets minor/patch", () => {
    expect(bumpVersion("1.4.7", "major")).toBe("2.0.0");
  });

  test("bumps the minor version and resets patch", () => {
    expect(bumpVersion("1.4.7", "minor")).toBe("1.5.0");
  });

  test("bumps the patch version", () => {
    expect(bumpVersion("1.4.7", "patch")).toBe("1.4.8");
  });

  test("returns the same version when bump type is 'none'", () => {
    expect(bumpVersion("1.4.7", "none")).toBe("1.4.7");
  });
});
