// RED: drive out the core label assignment logic built on top of matchGlob.
import { describe, expect, test } from "bun:test";
import { assignLabels, type LabelRule } from "./label-assigner.ts";

const RULES: LabelRule[] = [
  { pattern: "docs/**", label: "documentation", priority: 10 },
  { pattern: "src/api/**", label: "api", priority: 30 },
  { pattern: "*.test.*", label: "tests", priority: 20 },
  { pattern: "src/**", label: "source", priority: 5 },
];

describe("assignLabels", () => {
  test("a single file gets the label of its matching rule", () => {
    const result = assignLabels(["docs/intro.md"], RULES);
    expect(result.labels).toEqual(["documentation"]);
  });

  test("one file can receive multiple labels from multiple matching rules", () => {
    // src/api/users.test.ts matches: src/api/** (api), *.test.* (tests),
    // and src/** (source). Labels are ordered by descending priority.
    const result = assignLabels(["src/api/users.test.ts"], RULES);
    expect(result.labels).toEqual(["api", "tests", "source"]);
  });

  test("labels from multiple files are merged into one deduplicated set", () => {
    const result = assignLabels(
      ["docs/a.md", "docs/b.md", "src/api/x.ts"],
      RULES,
    );
    // api (30) before documentation (10); documentation only appears once.
    expect(result.labels).toEqual(["api", "documentation", "source"]);
  });

  test("priority breaks ordering; declaration order breaks ties", () => {
    const tie: LabelRule[] = [
      { pattern: "a/**", label: "alpha", priority: 1 },
      { pattern: "b/**", label: "beta", priority: 1 },
    ];
    const result = assignLabels(["b/1", "a/1"], tie);
    expect(result.labels).toEqual(["alpha", "beta"]);
  });

  test("a file matching no rule contributes nothing and is reported", () => {
    const result = assignLabels(["unmatched.xyz"], RULES);
    expect(result.labels).toEqual([]);
    expect(result.unmatched).toEqual(["unmatched.xyz"]);
  });

  test("priority defaults to 0 when omitted", () => {
    const rules: LabelRule[] = [
      { pattern: "*.md", label: "docs" },
      { pattern: "*.md", label: "high", priority: 100 },
    ];
    const result = assignLabels(["readme.md"], rules);
    expect(result.labels).toEqual(["high", "docs"]);
  });
});
