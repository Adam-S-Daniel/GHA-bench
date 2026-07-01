import { describe, expect, test } from "bun:test";
import { createMockLicenseLookup, loadLicenseMapFromFile } from "../src/licenseLookup";

// RED: fails until src/licenseLookup.ts exports these.
describe("createMockLicenseLookup", () => {
  test("resolves a license by exact name@version key", async () => {
    const lookup = createMockLicenseLookup({ "left-pad@1.3.0": "MIT" });

    const license = await lookup({ name: "left-pad", version: "1.3.0" });

    expect(license).toBe("MIT");
  });

  test("falls back to a name-only key when no exact version match exists", async () => {
    const lookup = createMockLicenseLookup({ "left-pad": "MIT" });

    const license = await lookup({ name: "left-pad", version: "9.9.9" });

    expect(license).toBe("MIT");
  });

  test("prefers the exact name@version match over the name-only fallback", async () => {
    const lookup = createMockLicenseLookup({
      "left-pad": "MIT",
      "left-pad@2.0.0": "Apache-2.0",
    });

    const license = await lookup({ name: "left-pad", version: "2.0.0" });

    expect(license).toBe("Apache-2.0");
  });

  test("returns null when the dependency is not in the mock data", async () => {
    const lookup = createMockLicenseLookup({});

    const license = await lookup({ name: "mystery-pkg", version: "0.1.0" });

    expect(license).toBeNull();
  });
});

describe("loadLicenseMapFromFile", () => {
  test("reads a JSON file mapping dependencies to license identifiers", () => {
    const map = loadLicenseMapFromFile("tests/fixtures/license-data.sample.json");

    expect(map).toEqual({
      "left-pad@1.3.0": "MIT",
      "old-gpl-lib@2.0.0": "GPL-3.0",
    });
  });

  test("throws a clear error for a missing file", () => {
    expect(() => loadLicenseMapFromFile("tests/fixtures/no-such-file.json")).toThrow(
      /not found/i,
    );
  });
});
