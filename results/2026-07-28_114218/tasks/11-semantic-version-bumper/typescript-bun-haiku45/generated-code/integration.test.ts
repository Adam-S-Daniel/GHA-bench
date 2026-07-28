import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import * as fs from "fs";
import * as path from "path";
import { bumpVersion } from "./version-bumper";
import { fixtures } from "./test-fixtures";

const TEST_DIR = "/tmp/version-bumper-integration";

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

describe("Integration Tests", () => {
  it("should handle patch version bump scenario", () => {
    const fixture = fixtures.patchBump;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });

    const updated = JSON.parse(fs.readFileSync(testFile, "utf-8"));
    expect(updated.version).toBe(fixture.expectedVersion);
  });

  it("should handle minor version bump scenario", () => {
    const fixture = fixtures.minorBump;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should handle major version bump with exclamation syntax", () => {
    const fixture = fixtures.majorBumpExclamation;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should handle major version bump with BREAKING CHANGE footer", () => {
    const fixture = fixtures.majorBumpFooter;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should handle mixed breaking and regular changes", () => {
    const fixture = fixtures.mixedCommits;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should not bump for non-conventional commits", () => {
    const fixture = fixtures.noConventionalCommits;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
  });

  it("should handle commits with scope", () => {
    const fixture = fixtures.withScope;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should handle pre-release versions", () => {
    const fixture = fixtures.preReleaseToRelease;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
  });

  it("should handle large minor jump from small base", () => {
    const fixture = fixtures.largeMinorJump;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
  });

  it("should handle real-world scenario", () => {
    const fixture = fixtures.realWorldScenario;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    fixture.expectedChangelog.forEach((item) => {
      expect(result.changelog).toContain(item);
    });
  });

  it("should work with VERSION file format", () => {
    const fixture = fixtures.minorBump;
    const testFile = path.join(TEST_DIR, "VERSION");
    fs.writeFileSync(testFile, fixture.currentVersion);

    const result = bumpVersion(testFile, fixture.commits);

    expect(result.newVersion).toBe(fixture.expectedVersion);
    const content = fs.readFileSync(testFile, "utf-8").trim();
    expect(content).toBe(fixture.expectedVersion);
  });

  it("should preserve package.json structure", () => {
    const testFile = path.join(TEST_DIR, "package.json");
    const original = {
      name: "test-pkg",
      version: "1.0.0",
      description: "A test package",
      main: "index.js",
      keywords: ["test"],
      author: "Test Author",
      license: "MIT",
    };
    fs.writeFileSync(testFile, JSON.stringify(original, null, 2));

    bumpVersion(testFile, ["feat: new feature"]);

    const updated = JSON.parse(fs.readFileSync(testFile, "utf-8"));
    expect(updated.name).toBe(original.name);
    expect(updated.description).toBe(original.description);
    expect(updated.main).toBe(original.main);
    expect(updated.keywords).toEqual(original.keywords);
    expect(updated.author).toBe(original.author);
    expect(updated.license).toBe(original.license);
    expect(updated.version).toBe("1.1.0");
  });

  it("should generate properly formatted changelog", () => {
    const fixture = fixtures.realWorldScenario;
    const testFile = path.join(TEST_DIR, "package.json");
    fs.writeFileSync(
      testFile,
      JSON.stringify({ name: "test", version: fixture.currentVersion })
    );

    const result = bumpVersion(testFile, fixture.commits);

    // Check format
    expect(result.changelog).toContain("##");
    expect(result.changelog).toContain("###");
    expect(result.changelog).toMatch(/\d{4}-\d{2}-\d{2}/); // Date format
    expect(result.changelog).toContain("Features");
    expect(result.changelog).toContain("Bug Fixes");
  });
});
