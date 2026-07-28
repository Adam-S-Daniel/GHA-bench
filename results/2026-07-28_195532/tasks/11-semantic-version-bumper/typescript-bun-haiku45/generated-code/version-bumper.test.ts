import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import {
  parseVersion,
  bumpVersion,
  parseCommits,
  determineVersionBump,
  readPackageJson,
  writePackageJson,
  generateChangelog,
  getCommitLog,
} from "./version-bumper";
import { writeFileSync, readFileSync, rmSync } from "fs";

describe("parseVersion", () => {
  it("should parse a valid semantic version string", () => {
    const version = parseVersion("1.2.3");
    expect(version).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  it("should parse version with leading v", () => {
    const version = parseVersion("v2.0.0");
    expect(version).toEqual({ major: 2, minor: 0, patch: 0 });
  });

  it("should throw on invalid version format", () => {
    expect(() => parseVersion("invalid")).toThrow();
    expect(() => parseVersion("1.2")).toThrow();
  });
});

describe("bumpVersion", () => {
  it("should bump patch version on fix commit", () => {
    const bumped = bumpVersion({ major: 1, minor: 2, patch: 3 }, "patch");
    expect(bumped).toEqual({ major: 1, minor: 2, patch: 4 });
  });

  it("should bump minor version and reset patch on feat commit", () => {
    const bumped = bumpVersion({ major: 1, minor: 2, patch: 3 }, "minor");
    expect(bumped).toEqual({ major: 1, minor: 3, patch: 0 });
  });

  it("should bump major version and reset minor/patch on breaking change", () => {
    const bumped = bumpVersion({ major: 1, minor: 2, patch: 3 }, "major");
    expect(bumped).toEqual({ major: 2, minor: 0, patch: 0 });
  });
});

describe("parseCommits", () => {
  it("should parse fix commits", () => {
    const commits = parseCommits(["fix: handle edge case"]);
    expect(commits).toHaveLength(1);
    expect(commits[0]).toEqual({
      type: "fix",
      description: "handle edge case",
      isBreaking: false,
    });
  });

  it("should parse feat commits", () => {
    const commits = parseCommits(["feat: add new feature"]);
    expect(commits).toHaveLength(1);
    expect(commits[0].type).toBe("feat");
  });

  it("should detect breaking changes with BREAKING CHANGE", () => {
    const commits = parseCommits(["feat: redesign API\n\nBREAKING CHANGE: old API removed"]);
    expect(commits[0].isBreaking).toBe(true);
  });

  it("should detect breaking changes with ! suffix", () => {
    const commits = parseCommits(["feat!: redesign API"]);
    expect(commits[0].isBreaking).toBe(true);
  });
});

describe("determineVersionBump", () => {
  it("should return patch for fix commits only", () => {
    const commits = parseCommits(["fix: bug fix", "fix: another fix"]);
    expect(determineVersionBump(commits)).toBe("patch");
  });

  it("should return minor for feat commits", () => {
    const commits = parseCommits(["feat: new feature", "fix: bug"]);
    expect(determineVersionBump(commits)).toBe("minor");
  });

  it("should return major for breaking changes", () => {
    const commits = parseCommits(["feat!: breaking change", "feat: feature"]);
    expect(determineVersionBump(commits)).toBe("major");
  });

  it("should return none for no commits", () => {
    expect(determineVersionBump([])).toBe("none");
  });
});

describe("readPackageJson", () => {
  let testFile: string;

  beforeEach(() => {
    testFile = "/tmp/test-package-" + Math.random().toString(36).slice(2) + ".json";
  });

  afterEach(() => {
    if (Bun.file(testFile).size > 0) rmSync(testFile);
  });

  it("should read version from package.json", () => {
    writeFileSync(testFile, JSON.stringify({ name: "test", version: "1.2.3" }));
    const version = readPackageJson(testFile);
    expect(version).toEqual({ major: 1, minor: 2, patch: 3 });
  });
});

describe("writePackageJson", () => {
  let testFile: string;

  beforeEach(() => {
    testFile = "/tmp/test-package-" + Math.random().toString(36).slice(2) + ".json";
  });

  afterEach(() => {
    if (Bun.file(testFile).size > 0) rmSync(testFile);
  });

  it("should write version to package.json", () => {
    writeFileSync(testFile, JSON.stringify({ name: "test", version: "1.0.0" }));
    writePackageJson(testFile, { major: 2, minor: 1, patch: 0 });
    const content = JSON.parse(readFileSync(testFile, "utf-8"));
    expect(content.version).toBe("2.1.0");
  });
});

describe("generateChangelog", () => {
  it("should generate changelog from commits", () => {
    const commits = parseCommits([
      "feat: add new feature",
      "fix: bug fix",
      "feat: another feature",
    ]);
    const changelog = generateChangelog(commits);
    expect(changelog).toContain("Features");
    expect(changelog).toContain("add new feature");
    expect(changelog).toContain("another feature");
    expect(changelog).toContain("Bug Fixes");
    expect(changelog).toContain("bug fix");
  });
});

describe("getCommitLog", () => {
  it("should extract messages from commit log format", () => {
    const logOutput = "feat: feature 1\nfix: fix 1\nfeat: feature 2";
    const messages = logOutput.split("\n").filter((l) => l.trim());
    expect(messages).toHaveLength(3);
  });
});

describe("integration test", () => {
  let testFile: string;

  beforeEach(() => {
    testFile = "/tmp/test-pkg-" + Math.random().toString(36).slice(2) + ".json";
  });

  afterEach(() => {
    if (Bun.file(testFile).size > 0) rmSync(testFile);
  });

  it("should update package.json version end-to-end", () => {
    // Setup: create initial package.json
    writeFileSync(testFile, JSON.stringify({ name: "test", version: "0.1.0" }));

    // Parse commits and determine bump
    const commits = parseCommits(["feat: new feature", "fix: small fix"]);
    const bumpType = determineVersionBump(commits);
    expect(bumpType).toBe("minor");

    // Read, bump, write
    const currentVersion = readPackageJson(testFile);
    const newVersion = bumpVersion(currentVersion, bumpType);
    writePackageJson(testFile, newVersion);

    // Verify
    const updated = readPackageJson(testFile);
    expect(updated).toEqual({ major: 0, minor: 2, patch: 0 });
  });
});
