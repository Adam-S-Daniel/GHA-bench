/**
 * TDD Cycle 3 (RED): parsing + validating rule config and changed-file lists
 * from untyped JSON, with meaningful error messages.
 */
import { describe, expect, test } from "bun:test";
import {
  ConfigError,
  parseChangedFiles,
  parseRules,
} from "../src/label-assigner.ts";

describe("parseRules", () => {
  test("accepts a valid rules array (bare or wrapped in {rules})", () => {
    const raw = [{ pattern: "docs/**", labels: ["documentation"] }];
    expect(parseRules(raw)).toEqual(raw);
    expect(parseRules({ rules: raw })).toEqual(raw);
  });

  test("rejects non-array input", () => {
    expect(() => parseRules("nope")).toThrow(ConfigError);
    expect(() => parseRules("nope")).toThrow(/rules config must be an array/i);
  });

  test("rejects a rule with a missing or empty pattern", () => {
    expect(() => parseRules([{ pattern: "", labels: ["x"] }])).toThrow(
      /rule #1: "pattern" must be a non-empty string/i,
    );
    expect(() => parseRules([{ labels: ["x"] }])).toThrow(ConfigError);
  });

  test("rejects a rule without a non-empty labels array of strings", () => {
    expect(() => parseRules([{ pattern: "a/**", labels: [] }])).toThrow(
      /rule #1: "labels" must be a non-empty array of strings/i,
    );
    expect(() => parseRules([{ pattern: "a/**", labels: [42] }])).toThrow(
      ConfigError,
    );
  });

  test("rejects a non-numeric priority, mentioning the offending rule", () => {
    const rules = [
      { pattern: "a/**", labels: ["a"] },
      { pattern: "b/**", labels: ["b"], priority: "high" },
    ];
    expect(() => parseRules(rules)).toThrow(
      /rule #2: "priority" must be a finite number/i,
    );
  });
});

describe("parseChangedFiles", () => {
  test("accepts an array of path strings", () => {
    expect(parseChangedFiles(["a.ts", "docs/b.md"])).toEqual([
      "a.ts",
      "docs/b.md",
    ]);
  });

  test("rejects non-array or non-string entries", () => {
    expect(() => parseChangedFiles({})).toThrow(
      /changed files must be an array of path strings/i,
    );
    expect(() => parseChangedFiles(["ok", 7])).toThrow(ConfigError);
  });
});
