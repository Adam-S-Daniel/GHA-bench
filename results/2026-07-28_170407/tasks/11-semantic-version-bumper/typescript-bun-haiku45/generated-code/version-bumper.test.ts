import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import * as fs from "fs";
import * as path from "path";
import {
  BumpResult,
  parseVersion,
  bumpVersion,
  updateVersion,
  parseGitLog,
} from "./version-bumper";

describe("parseVersion", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = `/tmp/test-parse-version-${Date.now()}`;
    fs.mkdirSync(tempDir, { recursive: true });
  });

  afterEach(() => {
    if (fs.existsSync(tempDir)) fs.rmSync(tempDir, { recursive: true });
  });

  it("should parse a valid semantic version from package.json", () => {
    fs.writeFileSync(
      path.join(tempDir, "package.json"),
      JSON.stringify({ version: "1.2.3" }, null, 2)
    );

    const result = parseVersion(path.join(tempDir, "package.json"));
    expect(result).toBe("1.2.3");
  });

  it("should parse version with prerelease tag", () => {
    fs.writeFileSync(
      path.join(tempDir, "package.json"),
      JSON.stringify({ version: "2.0.0-beta.1" }, null, 2)
    );

    const result = parseVersion(path.join(tempDir, "package.json"));
    expect(result).toBe("2.0.0-beta.1");
  });
});

describe("bumpVersion", () => {
  it("should bump minor version for feat commit", () => {
    const commits = ["feat: add new feature"];
    const result = bumpVersion("1.0.0", commits);
    expect(result.newVersion).toBe("1.1.0");
    expect(result.changeType).toBe("minor");
  });

  it("should bump patch version for fix commit", () => {
    const commits = ["fix: correct behavior"];
    const result = bumpVersion("1.0.0", commits);
    expect(result.newVersion).toBe("1.0.1");
    expect(result.changeType).toBe("patch");
  });

  it("should bump major version for breaking change", () => {
    const commits = ["feat: redesign API\n\nBREAKING CHANGE: old API removed"];
    const result = bumpVersion("1.0.0", commits);
    expect(result.newVersion).toBe("2.0.0");
    expect(result.changeType).toBe("major");
  });

  it("should prioritize breaking changes over features and fixes", () => {
    const commits = [
      "feat: add feature",
      "fix: bug fix",
      "feat!: breaking feature",
    ];
    const result = bumpVersion("1.0.0", commits);
    expect(result.newVersion).toBe("2.0.0");
  });

  it("should handle multiple minor bumps (use highest priority)", () => {
    const commits = ["feat: feature one", "feat: feature two"];
    const result = bumpVersion("1.0.0", commits);
    expect(result.newVersion).toBe("1.1.0");
  });

  it("should not bump version when no conventional commits", () => {
    const commits = ["random commit message"];
    const result = bumpVersion("1.0.0", commits);
    expect(result.changeType).toBe("none");
    expect(result.newVersion).toBe("1.0.0");
  });

  it("should generate changelog with features and fixes", () => {
    const commits = [
      "feat: add new API endpoint",
      "fix: resolve null pointer issue",
    ];
    const result = bumpVersion("1.0.0", commits);
    expect(result.changelog).toContain("### Features");
    expect(result.changelog).toContain("### Bug Fixes");
    expect(result.changelog).toContain("add new API endpoint");
    expect(result.changelog).toContain("resolve null pointer issue");
  });
});

describe("updateVersion", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = `/tmp/test-update-version-${Date.now()}`;
    fs.mkdirSync(tempDir, { recursive: true });
  });

  afterEach(() => {
    if (fs.existsSync(tempDir)) fs.rmSync(tempDir, { recursive: true });
  });

  it("should update version in package.json", () => {
    const pkgPath = path.join(tempDir, "package.json");
    fs.writeFileSync(
      pkgPath,
      JSON.stringify({ version: "1.0.0", name: "test" }, null, 2)
    );

    updateVersion(pkgPath, "1.1.0");

    const updated = JSON.parse(fs.readFileSync(pkgPath, "utf-8"));
    expect(updated.version).toBe("1.1.0");
    expect(updated.name).toBe("test");
  });

  it("should append changelog to CHANGELOG.md", () => {
    const pkgPath = path.join(tempDir, "package.json");
    const changelogPath = path.join(tempDir, "CHANGELOG.md");
    const initialContent = "# Changelog\n\n";
    fs.writeFileSync(pkgPath, JSON.stringify({ version: "1.0.0" }, null, 2));
    fs.writeFileSync(changelogPath, initialContent);

    const newChangelog = "## [1.1.0] - 2026-07-28\n### Features\n- new feature\n";
    updateVersion(pkgPath, "1.1.0", newChangelog);

    const updated = fs.readFileSync(changelogPath, "utf-8");
    expect(updated).toContain("## [1.1.0]");
    expect(updated).toContain("new feature");
  });
});

describe("parseGitLog", () => {
  it("should parse git log output into commit messages", () => {
    // Format: git log --format=%H%n%s%n%b%n---END---
    const gitLog = `abc123
feat: add new endpoint

---END---
def456
fix: correct behavior

---END---
ghi789
feat: another feature

---END---`;

    const commits = parseGitLog(gitLog);
    expect(commits.length).toBe(3);
    expect(commits[0]).toBe("feat: add new endpoint");
    expect(commits[1]).toBe("fix: correct behavior");
    expect(commits[2]).toBe("feat: another feature");
  });

  it("should handle empty git log", () => {
    const commits = parseGitLog("");
    expect(commits.length).toBe(0);
  });

  it("should preserve multi-line commit messages with body", () => {
    const gitLog = `abc123
feat: add feature
This is a longer description
that spans multiple lines

---END---
def456
feat: another feature

---END---`;

    const commits = parseGitLog(gitLog);
    expect(commits.length).toBe(2);
    expect(commits[0]).toContain("feat: add feature");
    expect(commits[0]).toContain("This is a longer description");
  });

  it("should handle BREAKING CHANGE in body", () => {
    const gitLog = `abc123
feat: redesign API
BREAKING CHANGE: old endpoint removed

---END---`;

    const commits = parseGitLog(gitLog);
    expect(commits.length).toBe(1);
    expect(commits[0]).toContain("BREAKING CHANGE");
  });
});
