import { describe, expect, test } from "bun:test";
import { parsePackageJson, parseRequirementsTxt } from "./parser";

describe("parsePackageJson", () => {
  test("extracts dependency names and versions from dependencies and devDependencies", () => {
    const content = JSON.stringify({
      name: "sample",
      dependencies: {
        express: "^4.18.2",
        lodash: "4.17.21",
      },
      devDependencies: {
        typescript: "~5.0.0",
      },
    });

    const deps = parsePackageJson(content);

    expect(deps).toEqual(
      expect.arrayContaining([
        { name: "express", version: "^4.18.2" },
        { name: "lodash", version: "4.17.21" },
        { name: "typescript", version: "~5.0.0" },
      ])
    );
    expect(deps).toHaveLength(3);
  });

  test("returns an empty array when no dependencies are present", () => {
    const deps = parsePackageJson(JSON.stringify({ name: "empty" }));
    expect(deps).toEqual([]);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parsePackageJson("{ not valid json")).toThrow(/invalid JSON/i);
  });
});

describe("parseRequirementsTxt", () => {
  test("extracts names and versions from == pins", () => {
    const content = ["requests==2.31.0", "flask==2.3.2", "# a comment", "", "numpy==1.26.0"].join("\n");

    const deps = parseRequirementsTxt(content);

    expect(deps).toEqual([
      { name: "requests", version: "2.31.0" },
      { name: "flask", version: "2.3.2" },
      { name: "numpy", version: "1.26.0" },
    ]);
  });

  test("handles entries without a version as unknown", () => {
    const deps = parseRequirementsTxt("somepackage");
    expect(deps).toEqual([{ name: "somepackage", version: "unknown" }]);
  });
});
