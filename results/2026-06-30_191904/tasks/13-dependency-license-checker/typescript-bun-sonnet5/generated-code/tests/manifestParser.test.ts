import { describe, expect, test } from "bun:test";
import { parseManifest } from "../src/manifestParser";

// RED: this fails until src/manifestParser.ts exports parseManifest.
describe("parseManifest / package.json", () => {
  test("extracts dependencies and devDependencies with cleaned versions", () => {
    const deps = parseManifest("tests/fixtures/pkg-sample/package.json");

    expect(deps).toEqual([
      { name: "left-pad", version: "1.3.0" },
      { name: "old-gpl-lib", version: "2.0.0" },
      { name: "mystery-pkg", version: "0.1.0" },
      { name: "typescript", version: "5.4.0" },
    ]);
  });

  test("strips semver range prefixes like ^ ~ >= from versions", () => {
    const deps = parseManifest("tests/fixtures/pkg-ranges/package.json");

    expect(deps).toEqual([
      { name: "caret-dep", version: "1.2.3" },
      { name: "tilde-dep", version: "2.0.0" },
      { name: "gte-dep", version: "3.1.0" },
      { name: "star-dep", version: "*" },
    ]);
  });
});

describe("parseManifest / requirements.txt", () => {
  test("extracts package names and pinned versions, skipping comments and blanks", () => {
    const deps = parseManifest("tests/fixtures/req-sample/requirements.txt");

    expect(deps).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "flask", version: "2.0.0" },
      { name: "no-version-pkg", version: "*" },
    ]);
  });

  test("supports >=, <=, ~=, ==, and bare != specifiers", () => {
    const deps = parseManifest("tests/fixtures/req-operators/requirements.txt");

    expect(deps).toEqual([
      { name: "pkg-eq", version: "1.0.0" },
      { name: "pkg-gte", version: "2.0.0" },
      { name: "pkg-lte", version: "3.0.0" },
      { name: "pkg-tilde", version: "4.0.0" },
      { name: "pkg-ne", version: "5.0.0" },
    ]);
  });
});

describe("parseManifest / error handling", () => {
  test("throws a clear error for a missing file", () => {
    expect(() => parseManifest("tests/fixtures/does-not-exist.json")).toThrow(
      /not found/i,
    );
  });

  test("throws a clear error for an unsupported manifest type", () => {
    expect(() => parseManifest("tests/fixtures/unsupported.toml")).toThrow(
      /unsupported manifest/i,
    );
  });

  test("throws a clear error for malformed JSON", () => {
    expect(() => parseManifest("tests/fixtures/pkg-malformed/package.json")).toThrow(
      /invalid json/i,
    );
  });
});
