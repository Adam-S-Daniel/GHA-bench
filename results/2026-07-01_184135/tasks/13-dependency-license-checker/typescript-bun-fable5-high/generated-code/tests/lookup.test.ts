/**
 * Tests for FileLicenseLookup (RED first: src/lookup.ts does not exist).
 *
 * Approach: real license data would come from a registry; for testability the
 * CLI is wired to a LicenseLookup backed by a local JSON file mapping package
 * name -> SPDX license. That file *is* the mock in CI, and these tests build
 * it from temp fixtures.
 */
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadFileLicenseLookup } from "../src/lookup";

function writeTemp(content: string): string {
  const dir = mkdtempSync(join(tmpdir(), "license-db-"));
  const file = join(dir, "licenses.json");
  writeFileSync(file, content);
  return file;
}

describe("loadFileLicenseLookup", () => {
  test("resolves licenses from the JSON database, null for misses", async () => {
    const lookup = await loadFileLicenseLookup(
      writeTemp(JSON.stringify({ react: "MIT", "left-pad": "GPL-3.0" })),
    );
    expect(await lookup.getLicense("react", "18.2.0")).toBe("MIT");
    expect(await lookup.getLicense("left-pad", "1.3.0")).toBe("GPL-3.0");
    expect(await lookup.getLicense("nope", "1.0.0")).toBeNull();
  });

  test("throws a meaningful error when the database file is missing", async () => {
    await expect(loadFileLicenseLookup("/no/such/licenses.json")).rejects.toThrow(
      /license database.*\/no\/such\/licenses.json/i,
    );
  });

  test("throws a meaningful error when the database is not a string map", async () => {
    await expect(loadFileLicenseLookup(writeTemp('{"react": 42}'))).rejects.toThrow(
      /license database.*"react".*string/i,
    );
  });
});
