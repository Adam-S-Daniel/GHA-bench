import { expect, describe, it, beforeEach, afterEach } from "bun:test";
import { readPackageVersion, writePackageVersion } from "./files";
import { readFileSync, writeFileSync } from "fs";
import { mkdirSync, rmSync } from "fs";
import { join } from "path";

const testDir = "/tmp/version-bumper-test";
const testFile = join(testDir, "package.json");

describe("readPackageVersion", () => {
  beforeEach(() => {
    try {
      mkdirSync(testDir, { recursive: true });
    } catch {
      // Directory might already exist
    }
  });

  afterEach(() => {
    try {
      rmSync(testFile, { force: true });
      rmSync(testDir, { force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  it("should read version from package.json", () => {
    const content = JSON.stringify({ name: "test", version: "1.2.3" });
    writeFileSync(testFile, content);

    const version = readPackageVersion(testFile);
    expect(version).toBe("1.2.3");
  });

  it("should throw if file doesn't exist", () => {
    expect(() => readPackageVersion(testFile)).toThrow();
  });

  it("should throw if version field is missing", () => {
    const content = JSON.stringify({ name: "test" });
    writeFileSync(testFile, content);

    expect(() => readPackageVersion(testFile)).toThrow();
  });
});

describe("writePackageVersion", () => {
  beforeEach(() => {
    try {
      mkdirSync(testDir, { recursive: true });
    } catch {
      // Directory might already exist
    }
  });

  afterEach(() => {
    try {
      rmSync(testFile, { force: true });
      rmSync(testDir, { force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  it("should update version in package.json", () => {
    const content = JSON.stringify({ name: "test", version: "1.0.0" });
    writeFileSync(testFile, content);

    writePackageVersion(testFile, "1.1.0");

    const updated = JSON.parse(readFileSync(testFile, "utf-8"));
    expect(updated.version).toBe("1.1.0");
  });

  it("should preserve other fields", () => {
    const original = {
      name: "test-pkg",
      description: "A test package",
      version: "1.0.0",
      main: "index.js",
    };
    writeFileSync(testFile, JSON.stringify(original));

    writePackageVersion(testFile, "2.0.0");

    const updated = JSON.parse(readFileSync(testFile, "utf-8"));
    expect(updated.name).toBe("test-pkg");
    expect(updated.description).toBe("A test package");
    expect(updated.main).toBe("index.js");
    expect(updated.version).toBe("2.0.0");
  });
});
