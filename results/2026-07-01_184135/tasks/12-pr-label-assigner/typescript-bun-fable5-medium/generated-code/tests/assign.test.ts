/**
 * TDD Cycle 2 (RED): assignLabels — apply rules to a changed-file list.
 *
 * Priority semantics: each rule has an optional numeric `priority`
 * (default 0, higher wins). For a given FILE, when multiple rules match,
 * only the rules sharing the highest priority among the matches contribute
 * labels for that file. The final result is the sorted union across files.
 */
import { describe, expect, test } from "bun:test";
import { assignLabels, type LabelRule } from "../src/label-assigner.ts";

const RULES: LabelRule[] = [
  { pattern: "docs/**", labels: ["documentation"] },
  { pattern: "src/api/**", labels: ["api", "backend"] },
  { pattern: "*.test.*", labels: ["tests"] },
];

describe("assignLabels", () => {
  test("maps files to labels via glob rules", () => {
    expect(assignLabels(["docs/intro.md"], RULES)).toEqual(["documentation"]);
  });

  test("a single rule can contribute multiple labels", () => {
    expect(assignLabels(["src/api/users.ts"], RULES)).toEqual([
      "api",
      "backend",
    ]);
  });

  test("multiple rules can match one file (equal priority → union)", () => {
    expect(assignLabels(["src/api/users.test.ts"], RULES)).toEqual([
      "api",
      "backend",
      "tests",
    ]);
  });

  test("result is the deduplicated sorted union across all files", () => {
    const labels = assignLabels(
      ["docs/a.md", "docs/b.md", "src/api/x.ts", "README.md"],
      RULES,
    );
    expect(labels).toEqual(["api", "backend", "documentation"]);
  });

  test("returns an empty set when nothing matches", () => {
    expect(assignLabels(["Makefile"], RULES)).toEqual([]);
  });

  test("higher-priority rule wins a conflict on the same file", () => {
    const rules: LabelRule[] = [
      { pattern: "src/**", labels: ["source"], priority: 1 },
      { pattern: "src/generated/**", labels: ["generated"], priority: 10 },
    ];
    // Both rules match; only the priority-10 rule applies to this file.
    expect(assignLabels(["src/generated/schema.ts"], rules)).toEqual([
      "generated",
    ]);
    // A file matched only by the low-priority rule still gets its label.
    expect(assignLabels(["src/main.ts"], rules)).toEqual(["source"]);
  });

  test("equal top-priority rules all contribute labels", () => {
    const rules: LabelRule[] = [
      { pattern: "src/api/**", labels: ["api"], priority: 5 },
      { pattern: "**/*.ts", labels: ["typescript"], priority: 5 },
      { pattern: "src/**", labels: ["source"], priority: 1 },
    ];
    expect(assignLabels(["src/api/users.ts"], rules)).toEqual([
      "api",
      "typescript",
    ]);
  });
});
