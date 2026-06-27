import { describe, expect, test } from "bun:test";
import {
  assignLabels,
  matchesPattern,
  parseConfig,
  type Rule,
} from "./labeler.ts";

// ---------------------------------------------------------------------------
// matchesPattern: lowest-level primitive — does one path match one glob?
// ---------------------------------------------------------------------------
describe("matchesPattern", () => {
  test("matches a recursive directory glob (docs/**)", () => {
    expect(matchesPattern("docs/guide/intro.md", "docs/**")).toBe(true);
  });

  test("does not match a different top-level directory", () => {
    expect(matchesPattern("src/index.ts", "docs/**")).toBe(false);
  });

  test("matches nested API paths (src/api/**)", () => {
    expect(matchesPattern("src/api/v1/users.ts", "src/api/**")).toBe(true);
  });

  test("slash-less pattern matches by basename at any depth (*.test.*)", () => {
    expect(matchesPattern("src/api/users.test.ts", "*.test.*")).toBe(true);
    expect(matchesPattern("foo.test.js", "*.test.*")).toBe(true);
  });

  test("single star does not cross directory boundaries", () => {
    expect(matchesPattern("a/b/c.ts", "a/*.ts")).toBe(false);
    expect(matchesPattern("a/c.ts", "a/*.ts")).toBe(true);
  });

  test("extension glob matches by basename (*.md)", () => {
    expect(matchesPattern("README.md", "*.md")).toBe(true);
    expect(matchesPattern("docs/x.md", "*.md")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// assignLabels: core feature — given files + rules, produce the label set.
// ---------------------------------------------------------------------------
describe("assignLabels", () => {
  test("assigns a single label when one rule matches one file", () => {
    const rules: Rule[] = [{ pattern: "docs/**", label: "documentation" }];
    expect(assignLabels(["docs/intro.md"], rules)).toEqual(["documentation"]);
  });

  test("a single file can receive multiple labels", () => {
    const rules: Rule[] = [
      { pattern: "src/api/**", label: "api" },
      { pattern: "*.test.*", label: "tests" },
    ];
    // One file matches BOTH rules.
    expect(assignLabels(["src/api/users.test.ts"], rules).sort()).toEqual([
      "api",
      "tests",
    ]);
  });

  test("multiple files contribute to a shared, de-duplicated label set", () => {
    const rules: Rule[] = [
      { pattern: "docs/**", label: "documentation" },
      { pattern: "src/api/**", label: "api" },
    ];
    const files = ["docs/a.md", "docs/b.md", "src/api/x.ts"];
    expect(assignLabels(files, rules).sort()).toEqual(["api", "documentation"]);
  });

  test("orders conflicting labels by priority (descending)", () => {
    const rules: Rule[] = [
      { pattern: "**/*.ts", label: "code", priority: 1 },
      { pattern: "src/api/**", label: "api", priority: 10 },
      { pattern: "*.test.*", label: "tests", priority: 5 },
    ];
    // api(10) > tests(5) > code(1)
    expect(assignLabels(["src/api/users.test.ts"], rules)).toEqual([
      "api",
      "tests",
      "code",
    ]);
  });

  test("breaks priority ties by label name (ascending)", () => {
    const rules: Rule[] = [
      { pattern: "**", label: "zebra", priority: 1 },
      { pattern: "**", label: "alpha", priority: 1 },
    ];
    expect(assignLabels(["anything.txt"], rules)).toEqual(["alpha", "zebra"]);
  });

  test("returns an empty array when no rule matches", () => {
    const rules: Rule[] = [{ pattern: "docs/**", label: "documentation" }];
    expect(assignLabels(["src/index.ts"], rules)).toEqual([]);
  });

  test("returns an empty array for an empty file list", () => {
    const rules: Rule[] = [{ pattern: "docs/**", label: "documentation" }];
    expect(assignLabels([], rules)).toEqual([]);
  });

  test("throws a meaningful error on a malformed rule", () => {
    // @ts-expect-error intentionally invalid rule to test error handling
    expect(() => assignLabels(["a.ts"], [{ pattern: "a.ts" }])).toThrow(
      /string `pattern` and `label`/,
    );
  });
});

// ---------------------------------------------------------------------------
// parseConfig: turn JSON config text into validated Rule[].
// ---------------------------------------------------------------------------
describe("parseConfig", () => {
  test("parses a valid JSON config into rules", () => {
    const json = JSON.stringify({
      rules: [
        { pattern: "docs/**", label: "documentation", priority: 1 },
        { pattern: "src/api/**", label: "api", priority: 10 },
      ],
    });
    expect(parseConfig(json)).toEqual([
      { pattern: "docs/**", label: "documentation", priority: 1 },
      { pattern: "src/api/**", label: "api", priority: 10 },
    ]);
  });

  test("throws a meaningful error on invalid JSON", () => {
    expect(() => parseConfig("{ not json")).toThrow(/invalid JSON/i);
  });

  test("throws when the `rules` array is missing", () => {
    expect(() => parseConfig(JSON.stringify({ foo: 1 }))).toThrow(/rules/i);
  });

  test("throws when a rule is missing required fields", () => {
    const json = JSON.stringify({ rules: [{ pattern: "docs/**" }] });
    expect(() => parseConfig(json)).toThrow(/label/i);
  });
});
