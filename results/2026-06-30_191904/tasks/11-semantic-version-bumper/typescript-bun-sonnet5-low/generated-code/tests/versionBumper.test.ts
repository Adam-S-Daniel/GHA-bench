// RED: these tests are written before src/versionBumper.ts exists / has behavior.
import { describe, expect, test } from "bun:test";
import {
  parseVersion,
  determineBumpType,
  bumpVersion,
  generateChangelogEntry,
  readVersionFile,
  writeVersionFile,
  type BumpType,
  type SemVer,
} from "../src/versionBumper";

describe("parseVersion", () => {
  test("parses a well-formed semver string into its components", () => {
    expect(parseVersion("1.2.3")).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  test("parses a version embedded in a package.json-style object", () => {
    expect(parseVersion("0.0.1")).toEqual({ major: 0, minor: 0, patch: 1 });
  });

  test("throws a meaningful error on malformed version strings", () => {
    expect(() => parseVersion("not-a-version")).toThrow(
      /invalid semantic version/i,
    );
    expect(() => parseVersion("1.2")).toThrow(/invalid semantic version/i);
    expect(() => parseVersion("")).toThrow(/invalid semantic version/i);
  });
});

describe("determineBumpType", () => {
  test("returns 'patch' when only fix commits are present", () => {
    const commits = [
      "fix(parser): handle empty input string",
      "chore: update dev dependencies",
    ];
    expect(determineBumpType(commits)).toBe("patch");
  });

  test("returns 'minor' when a feat commit is present", () => {
    const commits = [
      "feat(auth): add OAuth login support",
      "fix(session): correct token refresh timing",
    ];
    expect(determineBumpType(commits)).toBe("minor");
  });

  test("returns 'major' when a breaking change is present via '!' marker", () => {
    const commits = ["feat(api)!: rename endpoint", "chore: bump lockfile"];
    expect(determineBumpType(commits)).toBe("major");
  });

  test("returns 'major' when a BREAKING CHANGE footer is present", () => {
    const commits = [
      "feat(api): add new v2 endpoints",
      "refactor: cleanup\n\nBREAKING CHANGE: removed old client",
    ];
    expect(determineBumpType(commits)).toBe("major");
  });

  test("returns 'none' when no conventional commit triggers a bump", () => {
    const commits = ["chore: tidy up ci config", "docs: fix typo"];
    expect(determineBumpType(commits)).toBe("none");
  });

  test("throws a meaningful error when given no commits", () => {
    expect(() => determineBumpType([])).toThrow(/no commits/i);
  });
});

describe("bumpVersion", () => {
  const base: SemVer = { major: 1, minor: 2, patch: 3 };

  test("bumps the patch number and resets nothing else", () => {
    expect(bumpVersion(base, "patch")).toEqual({
      major: 1,
      minor: 2,
      patch: 4,
    });
  });

  test("bumps the minor number and resets patch to 0", () => {
    expect(bumpVersion(base, "minor")).toEqual({
      major: 1,
      minor: 3,
      patch: 0,
    });
  });

  test("bumps the major number and resets minor and patch to 0", () => {
    expect(bumpVersion(base, "major")).toEqual({
      major: 2,
      minor: 0,
      patch: 0,
    });
  });

  test("returns the same version unchanged for 'none'", () => {
    expect(bumpVersion(base, "none")).toEqual(base);
  });
});

describe("generateChangelogEntry", () => {
  test("produces a markdown section grouping commits by type", () => {
    const commits = [
      "feat(auth): add OAuth login support",
      "fix(session): correct token refresh timing",
      "chore: update dev dependencies",
    ];
    const entry = generateChangelogEntry("1.2.0", commits);
    expect(entry).toContain("## 1.2.0");
    expect(entry).toContain("### Features");
    expect(entry).toContain("add OAuth login support");
    expect(entry).toContain("### Bug Fixes");
    expect(entry).toContain("correct token refresh timing");
  });
});

describe("readVersionFile / writeVersionFile", () => {
  test("reads the version out of a JSON version file", async () => {
    const version = await readVersionFile("fixtures/version.json");
    expect(version).toBe("1.1.0");
  });

  test("throws a meaningful error when the file does not exist", async () => {
    await expect(readVersionFile("fixtures/does-not-exist.json")).rejects.toThrow(
      /not found/i,
    );
  });

  test("writes the new version back to a JSON version file", async () => {
    const tmpPath = "fixtures/.tmp-version-write-test.json";
    await writeVersionFile(tmpPath, { major: 2, minor: 0, patch: 0 });
    const written = await readVersionFile(tmpPath);
    expect(written).toBe("2.0.0");
    await Bun.file(tmpPath).delete?.();
    const fs = await import("node:fs/promises");
    await fs.rm(tmpPath, { force: true });
  });
});

export type { BumpType };
