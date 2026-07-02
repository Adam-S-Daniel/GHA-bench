import { describe, expect, test } from "bun:test";
import { assignLabels } from "./labeler";
import type { LabelRule } from "./types";

// RED: assignLabels does not exist yet.
describe("assignLabels", () => {
  test("returns no labels when there are no rules", () => {
    expect(assignLabels(["docs/readme.md"], [])).toEqual([]);
  });

  test("returns no labels when no rule matches any file", () => {
    const rules: LabelRule[] = [{ pattern: "docs/**", label: "documentation" }];
    expect(assignLabels(["src/index.ts"], rules)).toEqual([]);
  });

  test("applies a label when a file matches its pattern", () => {
    const rules: LabelRule[] = [{ pattern: "docs/**", label: "documentation" }];
    expect(assignLabels(["docs/readme.md"], rules)).toEqual(["documentation"]);
  });

  test("applies multiple labels when multiple rules match across files", () => {
    const rules: LabelRule[] = [
      { pattern: "docs/**", label: "documentation" },
      { pattern: "src/api/**", label: "api" },
    ];
    const files = ["docs/readme.md", "src/api/routes.ts"];
    expect(assignLabels(files, rules).sort()).toEqual(["api", "documentation"]);
  });

  test("applies multiple labels to a single file matching multiple rules", () => {
    const rules: LabelRule[] = [
      { pattern: "src/api/**", label: "api" },
      { pattern: "*.test.*", label: "tests" },
    ];
    // A single changed file can independently satisfy more than one rule.
    expect(assignLabels(["src/api/routes.test.ts"], rules).sort()).toEqual(["api", "tests"]);
  });

  test("does not duplicate a label when several files trigger the same rule", () => {
    const rules: LabelRule[] = [{ pattern: "docs/**", label: "documentation" }];
    const files = ["docs/a.md", "docs/b.md"];
    expect(assignLabels(files, rules)).toEqual(["documentation"]);
  });

  test("resolves conflicts within an exclusiveGroup by highest priority", () => {
    const rules: LabelRule[] = [
      { pattern: "**/*", label: "size/small", exclusiveGroup: "size", priority: 1 },
      { pattern: "**/*", label: "size/large", exclusiveGroup: "size", priority: 5 },
    ];
    // Both rules match, but only the higher-priority label should survive.
    expect(assignLabels(["src/index.ts"], rules)).toEqual(["size/large"]);
  });

  test("exclusiveGroup labels combine with ungrouped labels", () => {
    const rules: LabelRule[] = [
      { pattern: "**/*", label: "size/small", exclusiveGroup: "size", priority: 1 },
      { pattern: "**/*", label: "size/large", exclusiveGroup: "size", priority: 5 },
      { pattern: "docs/**", label: "documentation" },
    ];
    expect(assignLabels(["docs/readme.md"], rules).sort()).toEqual([
      "documentation",
      "size/large",
    ]);
  });

  test("breaks priority ties by earliest rule in the list", () => {
    const rules: LabelRule[] = [
      { pattern: "**/*", label: "first", exclusiveGroup: "g", priority: 3 },
      { pattern: "**/*", label: "second", exclusiveGroup: "g", priority: 3 },
    ];
    expect(assignLabels(["a.ts"], rules)).toEqual(["first"]);
  });

  test("treats missing priority as priority 0", () => {
    const rules: LabelRule[] = [
      { pattern: "**/*", label: "default", exclusiveGroup: "g" },
      { pattern: "**/*", label: "boosted", exclusiveGroup: "g", priority: 1 },
    ];
    expect(assignLabels(["a.ts"], rules)).toEqual(["boosted"]);
  });

  test("throws a meaningful error for a rule missing a pattern", () => {
    const rules = [{ label: "documentation" }] as unknown as LabelRule[];
    expect(() => assignLabels(["docs/readme.md"], rules)).toThrow(/pattern/i);
  });

  test("throws a meaningful error for a rule missing a label", () => {
    const rules = [{ pattern: "docs/**" }] as unknown as LabelRule[];
    expect(() => assignLabels(["docs/readme.md"], rules)).toThrow(/label/i);
  });
});
