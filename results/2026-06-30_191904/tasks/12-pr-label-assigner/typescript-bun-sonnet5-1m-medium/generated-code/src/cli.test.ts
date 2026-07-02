import { describe, expect, test } from "bun:test";
import { computeLabelsForFixture, readChangedFiles, readRules } from "./cli";

// RED: cli.ts does not exist yet.
describe("readRules", () => {
  test("parses the rules.json config into an array of LabelRule", () => {
    const rules = readRules("rules.json");
    expect(Array.isArray(rules)).toBe(true);
    expect(rules.length).toBeGreaterThan(0);
    expect(rules[0]).toHaveProperty("pattern");
    expect(rules[0]).toHaveProperty("label");
  });

  test("throws a meaningful error when the rules file does not exist", () => {
    expect(() => readRules("fixtures/does-not-exist.json")).toThrow(/not found|no such file/i);
  });
});

describe("readChangedFiles", () => {
  test("parses a fixture file into an array of file path strings", () => {
    const files = readChangedFiles("fixtures/case-docs-only.json");
    expect(files).toEqual(["docs/readme.md", "docs/guide/setup.md"]);
  });

  test("throws a meaningful error for a fixture that is not a JSON array", () => {
    expect(() => readChangedFiles("rules.json")).toThrow(/array of file paths/i);
  });
});

describe("computeLabelsForFixture", () => {
  test("docs-only fixture yields the documentation label", () => {
    const labels = computeLabelsForFixture("fixtures/case-docs-only.json", "rules.json");
    expect(labels).toEqual(["documentation"]);
  });

  test("api-and-tests fixture yields api (winning over backend) and tests", () => {
    const labels = computeLabelsForFixture("fixtures/case-api-and-tests.json", "rules.json");
    expect(labels).toEqual(["api", "tests"]);
  });

  test("mixed fixture yields api, ci, database, documentation", () => {
    const labels = computeLabelsForFixture("fixtures/case-mixed.json", "rules.json");
    expect(labels).toEqual(["api", "ci", "database", "documentation"]);
  });

  test("no-match fixture yields no labels", () => {
    const labels = computeLabelsForFixture("fixtures/case-no-match.json", "rules.json");
    expect(labels).toEqual([]);
  });
});
