// Red/Green TDD: this file starts with failing tests against the (not-yet-written) labeler module.
import { describe, expect, test } from "bun:test";
import { assignLabels, type LabelRule } from "./labeler";

// Mocked file lists simulating changed files in a PR.
const mockFiles = {
  docsOnly: ["docs/guide.md", "docs/README.md"],
  apiOnly: ["src/api/users.ts", "src/api/posts.ts"],
  testsOnly: ["src/utils/math.test.ts", "src/utils/string.test.ts"],
  mixed: ["docs/guide.md", "src/api/users.ts", "src/api/users.test.ts"],
  noMatch: ["random/file.txt"],
  empty: [] as string[],
};

const basicRules: LabelRule[] = [
  { pattern: "docs/**", label: "documentation", priority: 1 },
  { pattern: "src/api/**", label: "api", priority: 1 },
  { pattern: "*.test.*", label: "tests", priority: 10 },
];

describe("assignLabels", () => {
  test("matches a single glob rule against a set of docs files", () => {
    const labels = assignLabels(mockFiles.docsOnly, basicRules);
    expect(labels).toEqual(["documentation"]);
  });

  test("matches api rule for src/api/** files", () => {
    const labels = assignLabels(mockFiles.apiOnly, basicRules);
    expect(labels).toEqual(["api"]);
  });

  test("supports glob patterns like *.test.* across directories", () => {
    const labels = assignLabels(mockFiles.testsOnly, basicRules);
    expect(labels).toEqual(["tests"]);
  });

  test("applies multiple labels when files match multiple rules", () => {
    const labels = assignLabels(mockFiles.mixed, basicRules);
    // docs/guide.md -> documentation, src/api/users.ts -> api,
    // src/api/users.test.ts -> api AND tests
    expect(labels.sort()).toEqual(["api", "documentation", "tests"]);
  });

  test("returns empty array when no files match any rule", () => {
    const labels = assignLabels(mockFiles.noMatch, basicRules);
    expect(labels).toEqual([]);
  });

  test("returns empty array for an empty file list", () => {
    const labels = assignLabels(mockFiles.empty, basicRules);
    expect(labels).toEqual([]);
  });

  test("throws a meaningful error when rules array is empty", () => {
    expect(() => assignLabels(mockFiles.docsOnly, [])).toThrow(
      "No label rules provided",
    );
  });

  test("throws a meaningful error for a rule with an invalid empty pattern", () => {
    const badRules: LabelRule[] = [{ pattern: "", label: "bad", priority: 1 }];
    expect(() => assignLabels(mockFiles.docsOnly, badRules)).toThrow(
      "Rule has an empty pattern",
    );
  });

  test("priority ordering resolves conflicts when maxLabels/exclusive mode is used", () => {
    // When rules conflict and exclusiveMode is requested, only the highest
    // priority matching rule's label should be applied per file.
    const conflictingRules: LabelRule[] = [
      { pattern: "src/**", label: "low-priority", priority: 1 },
      { pattern: "src/api/**", label: "high-priority", priority: 5 },
    ];
    const labels = assignLabels(mockFiles.apiOnly, conflictingRules, {
      exclusive: true,
    });
    expect(labels).toEqual(["high-priority"]);
  });

  test("exclusive mode still applies multiple distinct highest-priority labels across different files", () => {
    const rules: LabelRule[] = [
      { pattern: "docs/**", label: "documentation", priority: 5 },
      { pattern: "src/api/**", label: "api", priority: 5 },
      { pattern: "src/**", label: "source", priority: 1 },
    ];
    const labels = assignLabels(
      ["docs/guide.md", "src/api/users.ts"],
      rules,
      { exclusive: true },
    );
    expect(labels.sort()).toEqual(["api", "documentation"]);
  });
});
