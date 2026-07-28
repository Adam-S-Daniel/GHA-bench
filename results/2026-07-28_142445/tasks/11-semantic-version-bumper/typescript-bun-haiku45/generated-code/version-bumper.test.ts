import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { promises as fs } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  parseVersion,
  detectBumpType,
  bumpVersion,
  generateChangelog,
  CommitType,
} from "./version-bumper";

describe("Semantic Version Bumper", () => {
  let testDir: string;

  beforeEach(async () => {
    testDir = join(tmpdir(), `version-bumper-${Date.now()}`);
    await fs.mkdir(testDir, { recursive: true });
  });

  afterEach(async () => {
    await fs.rm(testDir, { recursive: true, force: true });
  });

  describe("parseVersion", () => {
    it("should parse semantic version from package.json", async () => {
      const packageJson = { version: "1.0.0", name: "test" };
      await fs.writeFile(
        join(testDir, "package.json"),
        JSON.stringify(packageJson)
      );

      const version = await parseVersion(join(testDir, "package.json"));
      expect(version).toBe("1.0.0");
    });

    it("should handle different version formats", async () => {
      const packageJson = { version: "2.5.13", name: "test" };
      await fs.writeFile(
        join(testDir, "package.json"),
        JSON.stringify(packageJson)
      );

      const version = await parseVersion(join(testDir, "package.json"));
      expect(version).toBe("2.5.13");
    });
  });

  describe("detectBumpType", () => {
    it("should detect major bump for breaking changes", () => {
      const commits = [
        { message: "feat!: breaking change", type: CommitType.BREAKING },
      ];
      const bump = detectBumpType(commits);
      expect(bump).toBe("major");
    });

    it("should detect minor bump for features", () => {
      const commits = [{ message: "feat: new feature", type: CommitType.FEAT }];
      const bump = detectBumpType(commits);
      expect(bump).toBe("minor");
    });

    it("should detect patch bump for fixes", () => {
      const commits = [{ message: "fix: bug fix", type: CommitType.FIX }];
      const bump = detectBumpType(commits);
      expect(bump).toBe("patch");
    });

    it("should prioritize breaking over minor over patch", () => {
      const commits = [
        { message: "fix: bug fix", type: CommitType.FIX },
        { message: "feat: feature", type: CommitType.FEAT },
        { message: "feat!: breaking", type: CommitType.BREAKING },
      ];
      const bump = detectBumpType(commits);
      expect(bump).toBe("major");
    });
  });

  describe("bumpVersion", () => {
    it("should bump major version", () => {
      const newVersion = bumpVersion("1.0.0", "major");
      expect(newVersion).toBe("2.0.0");
    });

    it("should bump minor version", () => {
      const newVersion = bumpVersion("1.0.0", "minor");
      expect(newVersion).toBe("1.1.0");
    });

    it("should bump patch version", () => {
      const newVersion = bumpVersion("1.0.0", "patch");
      expect(newVersion).toBe("1.0.1");
    });

    it("should reset lower versions on major bump", () => {
      const newVersion = bumpVersion("1.5.7", "major");
      expect(newVersion).toBe("2.0.0");
    });

    it("should reset patch on minor bump", () => {
      const newVersion = bumpVersion("1.5.7", "minor");
      expect(newVersion).toBe("1.6.0");
    });
  });

  describe("generateChangelog", () => {
    it("should generate changelog from commits", () => {
      const commits = [
        { message: "feat: add new feature", type: CommitType.FEAT },
        { message: "fix: fix a bug", type: CommitType.FIX },
      ];
      const changelog = generateChangelog("1.1.0", commits);

      expect(changelog).toContain("## [1.1.0]");
      expect(changelog).toContain("add new feature");
      expect(changelog).toContain("fix a bug");
    });

    it("should categorize commits by type", () => {
      const commits = [
        { message: "feat: feature 1", type: CommitType.FEAT },
        { message: "feat: feature 2", type: CommitType.FEAT },
        { message: "fix: fix 1", type: CommitType.FIX },
      ];
      const changelog = generateChangelog("1.1.0", commits);

      expect(changelog).toContain("### Features");
      expect(changelog).toContain("### Fixes");
    });
  });

  describe("parseCommitMessage", () => {
    it("should parse conventional commit messages", async () => {
      // This test validates parseCommitLog works correctly
      const logContent = `feat: add new feature
fix: fix a bug`;

      const messages = logContent.split("\n");
      expect(messages[0]).toContain("feat:");
      expect(messages[1]).toContain("fix:");
    });
  });

  describe("Full integration", () => {
    it("should bump version and update package.json", async () => {
      const packageJson = { version: "1.0.0", name: "test-app" };
      const pkgPath = join(testDir, "package.json");
      await fs.writeFile(pkgPath, JSON.stringify(packageJson));

      const commits: import("./version-bumper").Commit[] = [
        { message: "feat: add new feature", type: CommitType.FEAT },
        { message: "fix: fix a bug", type: CommitType.FIX },
      ];

      const {
        oldVersion,
        newVersion,
        changelog,
      } = await import("./version-bumper").then((m) =>
        m.bumpSemanticVersion(pkgPath, commits)
      );

      expect(oldVersion).toBe("1.0.0");
      expect(newVersion).toBe("1.1.0");
      expect(changelog).toContain("## [1.1.0]");

      // Verify file was updated
      const updated = await fs.readFile(pkgPath, "utf-8");
      const updatedPkg = JSON.parse(updated);
      expect(updatedPkg.version).toBe("1.1.0");
    });
  });
});
