// Unit tests for the core label-assignment logic.
// TDD step 1 (red): these tests are written before src/labeler.ts exists,
// so `bun test` should fail with a module-not-found error until the
// minimum implementation is added.
import { describe, expect, test } from "bun:test";
import {
  matchesGlob,
  assignLabels,
  parseConfig,
  parseChangedFiles,
  type Rule,
} from "./labeler";

describe("matchesGlob", () => {
  test("matches a simple directory wildcard pattern", () => {
    expect(matchesGlob("docs/intro.md", "docs/**")).toBe(true);
  });

  test("does not match a path outside the wildcard directory", () => {
    expect(matchesGlob("src/index.ts", "docs/**")).toBe(false);
  });

  test("a slash-free pattern matches by basename at any depth", () => {
    // "*.test.*" has no "/", so it should match test files nested in any
    // directory, not just files at the repo root.
    expect(matchesGlob("src/api/users.test.ts", "*.test.*")).toBe(true);
  });

  test("a slash-free pattern still rejects non-matching basenames", () => {
    expect(matchesGlob("src/api/users.ts", "*.test.*")).toBe(false);
  });
});

describe("assignLabels", () => {
  const rules: Rule[] = [
    { pattern: "docs/**", label: "documentation" },
    { pattern: "src/api/**", label: "api" },
    { pattern: "*.test.*", label: "tests" },
  ];

  test("applies a single label when only one rule matches", () => {
    expect(assignLabels(["docs/intro.md"], rules)).toEqual(["documentation"]);
  });

  test("a single file can receive multiple labels from different rules", () => {
    // src/api/users.test.ts matches both the "api" and "tests" rules.
    const labels = assignLabels(["src/api/users.test.ts"], rules);
    expect(labels.sort()).toEqual(["api", "tests"]);
  });

  test("labels are de-duplicated across multiple matching files", () => {
    const labels = assignLabels(
      ["src/api/a.ts", "src/api/b.ts"],
      rules,
    );
    expect(labels).toEqual(["api"]);
  });

  test("returns an empty array when no rule matches", () => {
    expect(assignLabels(["Makefile"], rules)).toEqual([]);
  });

  test("orders matched labels by descending priority", () => {
    const priorityRules: Rule[] = [
      { pattern: "docs/**", label: "documentation", priority: 1 },
      { pattern: "src/api/**", label: "api", priority: 10 },
      { pattern: "*.test.*", label: "tests", priority: 5 },
    ];
    // All three rules match; output must be ordered highest-priority-first
    // regardless of the rules' or files' declaration order.
    const labels = assignLabels(
      ["src/api/users.test.ts", "docs/intro.md"],
      priorityRules,
    );
    expect(labels).toEqual(["api", "tests", "documentation"]);
  });

  test("breaks priority ties by label name for deterministic output", () => {
    const tiedRules: Rule[] = [
      { pattern: "b/**", label: "bravo", priority: 5 },
      { pattern: "a/**", label: "alpha", priority: 5 },
    ];
    const labels = assignLabels(["a/x.ts", "b/x.ts"], tiedRules);
    expect(labels).toEqual(["alpha", "bravo"]);
  });

  test("rules with no priority default to 0 and sort after prioritized ones", () => {
    const mixedRules: Rule[] = [
      { pattern: "src/**", label: "code" },
      { pattern: "src/api/**", label: "api", priority: 10 },
    ];
    const labels = assignLabels(["src/api/x.ts"], mixedRules);
    expect(labels).toEqual(["api", "code"]);
  });

  test("rejects a non-array file list with a clear error", () => {
    // @ts-expect-error intentionally passing a bad type to test the runtime guard
    expect(() => assignLabels("not-an-array", rules)).toThrow(/files/i);
  });

  test("rejects a non-array rule list with a clear error", () => {
    // @ts-expect-error intentionally passing a bad type to test the runtime guard
    expect(() => assignLabels([], "not-an-array")).toThrow(/rules/i);
  });
});

describe("parseConfig", () => {
  test("parses a valid rules document into Rule objects", () => {
    const json = JSON.stringify({
      rules: [
        { pattern: "docs/**", label: "documentation", priority: 1 },
        { pattern: "*.test.*", label: "tests" },
      ],
    });
    expect(parseConfig(json)).toEqual([
      { pattern: "docs/**", label: "documentation", priority: 1 },
      { pattern: "*.test.*", label: "tests" },
    ]);
  });

  test("rejects invalid JSON with a clear error message", () => {
    expect(() => parseConfig("{not json")).toThrow(/invalid JSON/i);
  });

  test("rejects a document missing the rules array", () => {
    expect(() => parseConfig(JSON.stringify({}))).toThrow(/rules/i);
  });

  test("rejects a rule missing a string pattern", () => {
    const json = JSON.stringify({ rules: [{ label: "tests" }] });
    expect(() => parseConfig(json)).toThrow(/pattern/i);
  });

  test("rejects a rule missing a string label", () => {
    const json = JSON.stringify({ rules: [{ pattern: "docs/**" }] });
    expect(() => parseConfig(json)).toThrow(/label/i);
  });

  test("rejects a rule with a non-numeric priority", () => {
    const json = JSON.stringify({
      rules: [{ pattern: "docs/**", label: "documentation", priority: "high" }],
    });
    expect(() => parseConfig(json)).toThrow(/priority/i);
  });
});

describe("parseChangedFiles", () => {
  test("splits a newline-delimited file list into trimmed paths", () => {
    expect(parseChangedFiles("docs/intro.md\nsrc/index.ts\n")).toEqual([
      "docs/intro.md",
      "src/index.ts",
    ]);
  });

  test("ignores blank lines and lines starting with #", () => {
    const text = "docs/intro.md\n\n# a comment\nsrc/index.ts\n   \n";
    expect(parseChangedFiles(text)).toEqual(["docs/intro.md", "src/index.ts"]);
  });

  test("returns an empty array for empty input", () => {
    expect(parseChangedFiles("")).toEqual([]);
  });
});
