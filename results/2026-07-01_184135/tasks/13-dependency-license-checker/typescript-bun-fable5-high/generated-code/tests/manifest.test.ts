/**
 * Tests for manifest parsing (RED first: src/manifest.ts does not exist yet).
 *
 * Approach: parseManifest() takes raw file content + a filename hint and
 * returns a normalized list of { name, version } dependencies, so the rest
 * of the pipeline never cares which ecosystem the manifest came from.
 */
import { describe, expect, test } from "bun:test";
import { parseManifest } from "../src/manifest";

describe("parseManifest: package.json", () => {
  test("extracts dependencies and devDependencies with versions", () => {
    const content = JSON.stringify({
      name: "demo",
      dependencies: { react: "^18.2.0", "left-pad": "1.3.0" },
      devDependencies: { typescript: "~5.4.0" },
    });

    const deps = parseManifest(content, "package.json");

    // Sorted by name, version range specifiers stripped to a bare version.
    expect(deps).toEqual([
      { name: "left-pad", version: "1.3.0" },
      { name: "react", version: "18.2.0" },
      { name: "typescript", version: "5.4.0" },
    ]);
  });

  test("returns an empty list when no dependency sections exist", () => {
    expect(parseManifest("{}", "package.json")).toEqual([]);
  });

  test("throws a meaningful error on malformed JSON", () => {
    expect(() => parseManifest("{ not json", "package.json")).toThrow(
      /package.json.*not valid JSON/i,
    );
  });
});

describe("parseManifest: requirements.txt", () => {
  test("extracts pinned and ranged requirements, ignoring comments/blanks", () => {
    const content = [
      "# production deps",
      "requests==2.31.0",
      "flask>=3.0.1  # web framework",
      "",
      "Django~=5.0.2",
    ].join("\n");

    const deps = parseManifest(content, "requirements.txt");

    expect(deps).toEqual([
      { name: "Django", version: "5.0.2" },
      { name: "flask", version: "3.0.1" },
      { name: "requests", version: "2.31.0" },
    ]);
  });

  test("uses '*' when a requirement has no version specifier", () => {
    expect(parseManifest("numpy\n", "requirements.txt")).toEqual([
      { name: "numpy", version: "*" },
    ]);
  });

  test("throws a meaningful error on an unparseable line", () => {
    expect(() => parseManifest("===???\n", "requirements.txt")).toThrow(
      /requirements.txt.*line 1/i,
    );
  });
});

describe("parseManifest: unsupported formats", () => {
  test("throws a meaningful error naming the file", () => {
    expect(() => parseManifest("", "Gemfile")).toThrow(/Unsupported manifest type.*Gemfile/);
  });
});
