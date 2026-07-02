// RED/GREEN cycle 2: manifest parsing.
// parseManifest dispatches on the file name:
//   - package.json      -> dependencies + devDependencies
//   - requirements.txt  -> pip-style lines (==, >=, bare names, comments)
// Malformed input must raise a meaningful error, never return garbage.
import { describe, expect, test } from "bun:test";
import { parseManifest, parseManifestFile } from "../src/parse";

describe("parseManifest (package.json)", () => {
  test("extracts dependencies and devDependencies with versions", () => {
    const content = JSON.stringify({
      dependencies: { "left-pad": "^1.3.0" },
      devDependencies: { typescript: "~5.4.0" },
    });
    expect(parseManifest(content, "package.json")).toEqual([
      { name: "left-pad", version: "^1.3.0" },
      { name: "typescript", version: "~5.4.0" },
    ]);
  });

  test("returns an empty list when no dependency sections exist", () => {
    expect(parseManifest("{}", "package.json")).toEqual([]);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseManifest("{not json", "package.json")).toThrow(
      /invalid JSON in package.json/i,
    );
  });
});

describe("parseManifest (requirements.txt)", () => {
  test("parses pinned, ranged, and bare entries, skipping comments/blanks", () => {
    const content = [
      "# a comment",
      "requests==2.31.0",
      "",
      "flask>=2.0",
      "plain-name",
    ].join("\n");
    expect(parseManifest(content, "requirements.txt")).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "flask", version: ">=2.0" },
      { name: "plain-name", version: "*" },
    ]);
  });
});

describe("parseManifest (unsupported)", () => {
  test("throws a meaningful error for unsupported manifest types", () => {
    expect(() => parseManifest("", "Gemfile")).toThrow(
      /unsupported manifest type: Gemfile/i,
    );
  });
});

describe("parseManifestFile", () => {
  test("reads and parses a package.json fixture from disk", async () => {
    const deps = await parseManifestFile(
      new URL("./fixtures/sample-package.json", import.meta.url).pathname,
    );
    // sample-package.json is named sample-*.json, so detection is by suffix
    expect(deps).toEqual([
      { name: "left-pad", version: "^1.3.0" },
      { name: "evil-lib", version: "2.0.0" },
      { name: "typescript", version: "~5.4.0" },
    ]);
  });

  test("reads and parses a requirements.txt fixture from disk", async () => {
    const deps = await parseManifestFile(
      new URL("./fixtures/sample-requirements.txt", import.meta.url).pathname,
    );
    expect(deps).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "copyleft-pkg", version: "1.0.0" },
      { name: "flask", version: ">=2.0" },
      { name: "plain-name", version: "*" },
    ]);
  });

  test("throws a meaningful error when the file does not exist", async () => {
    await expect(parseManifestFile("/no/such/manifest.json")).rejects.toThrow(
      /manifest file not found/i,
    );
  });
});
