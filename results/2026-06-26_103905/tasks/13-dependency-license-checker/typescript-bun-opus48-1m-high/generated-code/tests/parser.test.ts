/**
 * Tests for manifest parsing.
 *
 * The parser must turn the raw text of a dependency manifest into a normalized
 * list of { name, version } records, regardless of the manifest format
 * (package.json or requirements.txt). These tests are written FIRST (red),
 * then the implementation is filled in to make them pass (green).
 */
import { describe, expect, it } from "bun:test";
import { parseManifest } from "../src/parser.ts";
import type { Dependency } from "../src/types.ts";

describe("parseManifest - package.json", () => {
  it("extracts dependencies and devDependencies with versions", () => {
    const content = JSON.stringify({
      name: "demo",
      version: "1.0.0",
      dependencies: { "left-pad": "^1.3.0", lodash: "4.17.21" },
      devDependencies: { typescript: "~5.4.0" },
    });

    const deps: Dependency[] = parseManifest(content, "package.json");

    // Versions are normalized: leading range specifiers (^, ~, =, v) stripped.
    expect(deps).toEqual([
      { name: "left-pad", version: "1.3.0" },
      { name: "lodash", version: "4.17.21" },
      { name: "typescript", version: "5.4.0" },
    ]);
  });

  it("returns an empty list when there are no dependencies", () => {
    const content = JSON.stringify({ name: "demo", version: "1.0.0" });
    expect(parseManifest(content, "package.json")).toEqual([]);
  });

  it("throws a meaningful error on invalid JSON", () => {
    expect(() => parseManifest("{ not json", "package.json")).toThrow(
      /Failed to parse package\.json/,
    );
  });
});

describe("parseManifest - requirements.txt", () => {
  it("parses pinned requirements and ignores comments / blanks", () => {
    const content = [
      "# project requirements",
      "requests==2.31.0",
      "",
      "flask==3.0.0   # web framework",
      "PyYAML>=6.0",
    ].join("\n");

    const deps = parseManifest(content, "requirements.txt");

    expect(deps).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "flask", version: "3.0.0" },
      { name: "PyYAML", version: "6.0" },
    ]);
  });
});

describe("parseManifest - format detection / validation", () => {
  it("throws on an unsupported manifest type", () => {
    expect(() => parseManifest("", "Cargo.toml")).toThrow(
      /Unsupported manifest type/,
    );
  });
});
