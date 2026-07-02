// TDD step 1: manifest parsing. Red -> Green -> Refactor.
import { describe, expect, test } from "bun:test";
import { parsePackageJson, parseRequirementsTxt, parseManifest } from "../src/parser";

describe("parsePackageJson", () => {
  test("extracts dependencies and devDependencies with cleaned version strings", () => {
    const content = JSON.stringify({
      name: "demo",
      dependencies: { lodash: "^4.17.21", express: "~4.18.2" },
      devDependencies: { typescript: "5.4.0" },
    });

    const deps = parsePackageJson(content);

    expect(deps).toContainEqual({ name: "lodash", version: "4.17.21" });
    expect(deps).toContainEqual({ name: "express", version: "4.18.2" });
    expect(deps).toContainEqual({ name: "typescript", version: "5.4.0" });
    expect(deps).toHaveLength(3);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parsePackageJson("{ not valid json")).toThrow(/invalid package\.json/i);
  });
});

describe("parseRequirementsTxt", () => {
  test("extracts pinned dependencies and skips comments/blank lines", () => {
    const content = [
      "# a comment",
      "",
      "requests==2.31.0",
      "flask>=2.0.0",
      "click",
    ].join("\n");

    const deps = parseRequirementsTxt(content);

    expect(deps).toContainEqual({ name: "requests", version: "2.31.0" });
    expect(deps).toContainEqual({ name: "flask", version: "2.0.0" });
    expect(deps).toContainEqual({ name: "click", version: "unknown" });
    expect(deps).toHaveLength(3);
  });
});

describe("parseManifest", () => {
  test("dispatches based on file name", () => {
    const pkg = parseManifest("package.json", JSON.stringify({ dependencies: { chalk: "4.1.0" } }));
    expect(pkg).toEqual([{ name: "chalk", version: "4.1.0" }]);

    const req = parseManifest("requirements.txt", "requests==2.31.0");
    expect(req).toEqual([{ name: "requests", version: "2.31.0" }]);
  });

  test("throws a meaningful error for unsupported manifest types", () => {
    expect(() => parseManifest("Gemfile", "")).toThrow(/unsupported manifest/i);
  });
});
