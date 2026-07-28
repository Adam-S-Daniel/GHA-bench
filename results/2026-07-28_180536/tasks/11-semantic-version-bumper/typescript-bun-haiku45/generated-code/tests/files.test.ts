// TDD: Test file reading and writing operations

import { expect, test, describe, beforeEach, afterEach } from "bun:test";
import { readFileSync, writeFileSync, unlinkSync, existsSync } from "fs";
import {
  readVersionFromFile,
  writeVersionToFile,
  FileType,
} from "../src/files";

describe("readVersionFromFile", () => {
  const testFile = "/tmp/test-version-file.json";

  afterEach(() => {
    if (existsSync(testFile)) {
      unlinkSync(testFile);
    }
  });

  test("should read version from package.json", () => {
    const content = JSON.stringify({ version: "1.2.3" });
    writeFileSync(testFile, content);

    const version = readVersionFromFile(testFile, FileType.PACKAGE_JSON);
    expect(version).toBe("1.2.3");
  });

  test("should read version from version file", () => {
    writeFileSync(testFile, "2.3.4");
    const version = readVersionFromFile(testFile, FileType.VERSION);
    expect(version).toBe("2.3.4");
  });

  test("should read version with v prefix from version file", () => {
    writeFileSync(testFile, "v3.4.5\n");
    const version = readVersionFromFile(testFile, FileType.VERSION);
    expect(version).toBe("3.4.5");
  });

  test("should throw error if file does not exist", () => {
    expect(() => readVersionFromFile("/nonexistent/file", FileType.VERSION)).toThrow();
  });

  test("should throw error if version not found in package.json", () => {
    const content = JSON.stringify({ name: "test" });
    writeFileSync(testFile, content);
    expect(() => readVersionFromFile(testFile, FileType.PACKAGE_JSON)).toThrow();
  });
});

describe("writeVersionToFile", () => {
  const testFile = "/tmp/test-version-write.json";

  afterEach(() => {
    if (existsSync(testFile)) {
      unlinkSync(testFile);
    }
  });

  test("should write version to package.json", () => {
    const original = JSON.stringify({ name: "test", version: "1.0.0" });
    writeFileSync(testFile, original);

    writeVersionToFile(testFile, "2.0.0", FileType.PACKAGE_JSON);

    const content = JSON.parse(readFileSync(testFile, "utf-8"));
    expect(content.version).toBe("2.0.0");
    expect(content.name).toBe("test");
  });

  test("should write version to version file", () => {
    writeFileSync(testFile, "1.0.0");
    writeVersionToFile(testFile, "2.0.0", FileType.VERSION);

    const content = readFileSync(testFile, "utf-8").trim();
    expect(content).toBe("2.0.0");
  });
});
