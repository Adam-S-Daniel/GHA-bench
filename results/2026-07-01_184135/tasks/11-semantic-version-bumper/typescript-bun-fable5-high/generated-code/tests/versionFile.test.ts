/**
 * RED phase (cycle 4): tests for reading/writing the version from either a
 * plain VERSION file or a package.json. Uses throwaway temp dirs so tests
 * never touch the real project files.
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readVersionFile, writeVersionFile } from "../src/versionFile";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "svb-test-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("readVersionFile", () => {
  test("reads a plain VERSION file", () => {
    const file = join(dir, "VERSION");
    writeFileSync(file, "1.1.0\n");
    expect(readVersionFile(file)).toEqual({ major: 1, minor: 1, patch: 0 });
  });

  test("reads the version field of a package.json", () => {
    const file = join(dir, "package.json");
    writeFileSync(file, JSON.stringify({ name: "x", version: "2.3.4" }, null, 2));
    expect(readVersionFile(file)).toEqual({ major: 2, minor: 3, patch: 4 });
  });

  test("throws meaningfully when the file does not exist", () => {
    expect(() => readVersionFile(join(dir, "missing"))).toThrow(
      /Version file not found/,
    );
  });

  test("throws meaningfully when package.json has no version field", () => {
    const file = join(dir, "package.json");
    writeFileSync(file, JSON.stringify({ name: "x" }));
    expect(() => readVersionFile(file)).toThrow(/no "version" field/);
  });

  test("throws meaningfully on malformed package.json", () => {
    const file = join(dir, "package.json");
    writeFileSync(file, "{ not json");
    expect(() => readVersionFile(file)).toThrow(/not valid JSON/);
  });
});

describe("writeVersionFile", () => {
  test("writes a plain VERSION file with trailing newline", () => {
    const file = join(dir, "VERSION");
    writeFileSync(file, "1.1.0\n");
    writeVersionFile(file, { major: 1, minor: 2, patch: 0 });
    expect(readFileSync(file, "utf8")).toBe("1.2.0\n");
  });

  test("updates only the version field of package.json, preserving the rest", () => {
    const file = join(dir, "package.json");
    writeFileSync(file, JSON.stringify({ name: "x", version: "2.3.4", dependencies: {} }, null, 2) + "\n");
    writeVersionFile(file, { major: 3, minor: 0, patch: 0 });
    const parsed = JSON.parse(readFileSync(file, "utf8"));
    expect(parsed.version).toBe("3.0.0");
    expect(parsed.name).toBe("x");
    expect(parsed.dependencies).toEqual({});
  });
});
