import { describe, expect, test } from "bun:test";
import { parseManifest } from "../src/parser.ts";
import type { Dependency } from "../src/types.ts";

describe("parseManifest - package.json", () => {
  test("extracts names and versions from dependencies and devDependencies", () => {
    const content = JSON.stringify({
      name: "demo",
      dependencies: { "left-pad": "^1.3.0", lodash: "4.17.21" },
      devDependencies: { typescript: "~5.4.0" },
    });

    const deps: Dependency[] = parseManifest(content, "package.json");

    expect(deps).toEqual([
      { name: "left-pad", version: "^1.3.0" },
      { name: "lodash", version: "4.17.21" },
      { name: "typescript", version: "~5.4.0" },
    ]);
  });

  test("returns an empty array when no dependency sections exist", () => {
    const content = JSON.stringify({ name: "empty" });
    expect(parseManifest(content, "package.json")).toEqual([]);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseManifest("{ not json", "package.json")).toThrow(
      /Failed to parse package\.json/,
    );
  });
});

describe("parseManifest - requirements.txt", () => {
  test("extracts pinned and unpinned requirements, skipping comments/blanks", () => {
    const content = [
      "# a comment",
      "",
      "requests==2.31.0",
      "flask>=2.0.0",
      "  numpy == 1.26.0  ",
      "bare-package",
    ].join("\n");

    expect(parseManifest(content, "requirements.txt")).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "flask", version: "2.0.0" },
      { name: "numpy", version: "1.26.0" },
      { name: "bare-package", version: "*" },
    ]);
  });
});

describe("parseManifest - unsupported type", () => {
  test("throws for an unknown manifest type", () => {
    expect(() => parseManifest("", "Cargo.toml")).toThrow(
      /Unsupported manifest type/,
    );
  });
});
