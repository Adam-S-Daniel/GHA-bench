// TDD cycle 4a (RED): reading/writing the version from either a package.json
// or a plain-text VERSION file. Written before src/versionfile.ts.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readVersion, writeVersion } from "../src/versionfile";

const tmp = (): string => mkdtempSync(join(tmpdir(), "svb-"));

describe("readVersion", () => {
  test("reads the version field from a package.json", () => {
    const file = join(tmp(), "package.json");
    writeFileSync(file, JSON.stringify({ name: "x", version: "1.2.3" }));
    expect(readVersion(file)).toBe("1.2.3");
  });

  test("reads a plain VERSION file", () => {
    const file = join(tmp(), "VERSION");
    writeFileSync(file, "0.4.2\n");
    expect(readVersion(file)).toBe("0.4.2");
  });

  test("fails with a clear error when package.json has no version field", () => {
    const file = join(tmp(), "package.json");
    writeFileSync(file, JSON.stringify({ name: "x" }));
    expect(() => readVersion(file)).toThrow(/no "version" field/);
  });

  test("fails with a clear error when the file does not exist", () => {
    expect(() => readVersion(join(tmp(), "missing.json"))).toThrow(/not found/i);
  });
});

describe("writeVersion", () => {
  test("updates only the version field of a package.json, preserving formatting style", () => {
    const file = join(tmp(), "package.json");
    writeFileSync(file, JSON.stringify({ name: "x", version: "1.2.3", private: true }, null, 2) + "\n");
    writeVersion(file, "1.3.0");
    const parsed = JSON.parse(readFileSync(file, "utf8"));
    expect(parsed).toEqual({ name: "x", version: "1.3.0", private: true });
  });

  test("overwrites a plain VERSION file with the new version and a newline", () => {
    const file = join(tmp(), "VERSION");
    writeFileSync(file, "0.4.2\n");
    writeVersion(file, "0.5.0");
    expect(readFileSync(file, "utf8")).toBe("0.5.0\n");
  });
});
