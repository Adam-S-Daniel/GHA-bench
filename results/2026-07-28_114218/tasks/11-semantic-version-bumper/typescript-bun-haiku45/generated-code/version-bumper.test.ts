import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import * as fs from "fs";
import * as path from "path";
import {
  parseVersion,
  determineNextVersion,
  updateVersionFile,
  generateChangelog,
  bumpVersion,
  parseConventionalCommits,
} from "./version-bumper";

const TEST_DIR = "/tmp/version-bumper-tests";
const TEST_PACKAGE_JSON = path.join(TEST_DIR, "package.json");
const TEST_GIT_LOG = path.join(TEST_DIR, "git-log.txt");

beforeEach(() => {
  if (fs.existsSync(TEST_DIR)) {
    fs.rmSync(TEST_DIR, { recursive: true });
  }
  fs.mkdirSync(TEST_DIR, { recursive: true });
});

afterEach(() => {
  if (fs.existsSync(TEST_DIR)) {
    fs.rmSync(TEST_DIR, { recursive: true });
  }
});

describe("parseVersion", () => {
  it("should parse semantic version string", () => {
    const result = parseVersion("1.2.3");
    expect(result).toEqual({ major: 1, minor: 2, patch: 3 });
  });

  it("should parse version with leading v", () => {
    const result = parseVersion("v2.3.4");
    expect(result).toEqual({ major: 2, minor: 3, patch: 4 });
  });

  it("should throw on invalid version", () => {
    expect(() => parseVersion("not-a-version")).toThrow();
  });

  it("should parse version with pre-release", () => {
    const result = parseVersion("1.0.0-alpha");
    expect(result).toEqual({ major: 1, minor: 0, patch: 0 });
  });
});

describe("determineNextVersion", () => {
  it("should bump patch for fix commits", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const next = determineNextVersion(current, ["fix: bug fix"]);
    expect(next).toEqual({ major: 1, minor: 2, patch: 4 });
  });

  it("should bump minor for feat commits", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const next = determineNextVersion(current, [
      "feat: new feature",
      "fix: bug fix",
    ]);
    expect(next).toEqual({ major: 1, minor: 3, patch: 0 });
  });

  it("should bump major for breaking changes", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const next = determineNextVersion(current, ["feat!: breaking change"]);
    expect(next).toEqual({ major: 2, minor: 0, patch: 0 });
  });

  it("should bump major for BREAKING CHANGE footer", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const next = determineNextVersion(current, [
      "feat: feature\n\nBREAKING CHANGE: this is breaking",
    ]);
    expect(next).toEqual({ major: 2, minor: 0, patch: 0 });
  });

  it("should handle no commits without bumping", () => {
    const current = { major: 1, minor: 2, patch: 3 };
    const next = determineNextVersion(current, []);
    expect(next).toEqual({ major: 1, minor: 2, patch: 3 });
  });
});

describe("parseConventionalCommits", () => {
  it("should extract commit type from message", () => {
    const commits = parseConventionalCommits(["feat: new feature"]);
    expect(commits).toEqual([{ type: "feat", scope: undefined, message: "new feature", breaking: false }]);
  });

  it("should identify breaking changes with !", () => {
    const commits = parseConventionalCommits(["feat!: breaking change"]);
    expect(commits[0]).toEqual(
      expect.objectContaining({
        type: "feat",
        breaking: true,
        message: "breaking change",
      })
    );
  });

  it("should identify BREAKING CHANGE footer", () => {
    const commits = parseConventionalCommits([
      "feat: feature\n\nBREAKING CHANGE: describes breaking change",
    ]);
    expect(commits[0]).toEqual(
      expect.objectContaining({
        breaking: true,
      })
    );
  });

  it("should handle commits with scope", () => {
    const commits = parseConventionalCommits(["feat(api): new endpoint"]);
    expect(commits[0]).toEqual(
      expect.objectContaining({
        type: "feat",
        scope: "api",
        message: "new endpoint",
      })
    );
  });
});

describe("updateVersionFile", () => {
  it("should update version in package.json", () => {
    fs.writeFileSync(
      TEST_PACKAGE_JSON,
      JSON.stringify({ name: "test", version: "1.0.0" })
    );
    updateVersionFile(TEST_PACKAGE_JSON, "2.0.0");
    const content = JSON.parse(fs.readFileSync(TEST_PACKAGE_JSON, "utf-8"));
    expect(content.version).toBe("2.0.0");
  });

  it("should update version in VERSION file", () => {
    const versionFile = path.join(TEST_DIR, "VERSION");
    fs.writeFileSync(versionFile, "1.0.0");
    updateVersionFile(versionFile, "2.0.0");
    const content = fs.readFileSync(versionFile, "utf-8").trim();
    expect(content).toBe("2.0.0");
  });

  it("should preserve other fields in package.json", () => {
    fs.writeFileSync(
      TEST_PACKAGE_JSON,
      JSON.stringify({ name: "test", version: "1.0.0", description: "test pkg" })
    );
    updateVersionFile(TEST_PACKAGE_JSON, "2.0.0");
    const content = JSON.parse(fs.readFileSync(TEST_PACKAGE_JSON, "utf-8"));
    expect(content.name).toBe("test");
    expect(content.description).toBe("test pkg");
  });
});

describe("generateChangelog", () => {
  it("should generate changelog entry for multiple commits", () => {
    const changelog = generateChangelog("2.0.0", [
      "feat: new feature",
      "fix: bug fix",
    ]);
    expect(changelog).toContain("2.0.0");
    expect(changelog).toContain("new feature");
    expect(changelog).toContain("bug fix");
  });

  it("should include date in changelog", () => {
    const changelog = generateChangelog("2.0.0", ["feat: new feature"]);
    expect(changelog).toMatch(/\d{4}-\d{2}-\d{2}/);
  });

  it("should handle empty commits list", () => {
    const changelog = generateChangelog("2.0.0", []);
    expect(changelog).toContain("2.0.0");
  });

  it("should group commits by type", () => {
    const changelog = generateChangelog("2.0.0", [
      "feat: feature 1",
      "feat: feature 2",
      "fix: fix 1",
    ]);
    expect(changelog.indexOf("Feature")).toBeLessThan(changelog.indexOf("Fix"));
  });
});

describe("bumpVersion", () => {
  it("should bump version from package.json with commits", () => {
    fs.writeFileSync(
      TEST_PACKAGE_JSON,
      JSON.stringify({ name: "test", version: "1.0.0" })
    );
    const result = bumpVersion(TEST_PACKAGE_JSON, ["feat: new feature"]);
    expect(result.oldVersion).toBe("1.0.0");
    expect(result.newVersion).toBe("1.1.0");
    const updated = JSON.parse(fs.readFileSync(TEST_PACKAGE_JSON, "utf-8"));
    expect(updated.version).toBe("1.1.0");
  });

  it("should generate changelog in result", () => {
    fs.writeFileSync(
      TEST_PACKAGE_JSON,
      JSON.stringify({ name: "test", version: "1.0.0" })
    );
    const result = bumpVersion(TEST_PACKAGE_JSON, ["feat: new feature"]);
    expect(result.changelog).toContain("1.1.0");
  });

  it("should handle multiple bump scenarios", () => {
    fs.writeFileSync(
      TEST_PACKAGE_JSON,
      JSON.stringify({ name: "test", version: "0.5.2" })
    );
    const result = bumpVersion(TEST_PACKAGE_JSON, [
      "feat: feature",
      "fix!: breaking fix",
    ]);
    expect(result.newVersion).toBe("1.0.0");
  });
});
