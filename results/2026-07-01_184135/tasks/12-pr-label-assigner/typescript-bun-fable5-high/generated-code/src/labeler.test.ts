// TDD iteration 3 (RED): the rule engine. Given a list of changed file paths
// (the mocked "PR") and an ordered list of rules, compute the final label set.
import { describe, expect, test } from "bun:test";
import {
  assignLabels,
  parseChangedFiles,
  parseRules,
  type LabelRule,
} from "./labeler";

// Shared fixture: a typical repo's labeling rules.
const RULES: LabelRule[] = [
  { pattern: "docs/**", labels: ["documentation"] },
  { pattern: "src/api/**", labels: ["api", "backend"] },
  { pattern: "*.test.*", labels: ["tests"] },
  { pattern: ".github/**", labels: ["ci"] },
];

describe("assignLabels: basic path-to-label mapping", () => {
  test("a single matching file yields that rule's labels", () => {
    expect(assignLabels(["docs/readme.md"], RULES)).toEqual(["documentation"]);
  });

  test("one rule can attach multiple labels to one file", () => {
    expect(assignLabels(["src/api/users.ts"], RULES)).toEqual(["api", "backend"]);
  });

  test("labels are the union across all changed files, sorted and deduped", () => {
    const changed = [
      "docs/guide.md",
      "docs/faq.md", // second docs file must not duplicate "documentation"
      "src/api/auth.ts",
      "src/api/auth.test.ts", // matches both src/api/** and *.test.*
    ];
    expect(assignLabels(changed, RULES)).toEqual([
      "api",
      "backend",
      "documentation",
      "tests",
    ]);
  });

  test("files matching no rule contribute nothing", () => {
    expect(assignLabels(["LICENSE", "assets/logo.png"], RULES)).toEqual([]);
  });

  test("empty changed-file list yields an empty label set", () => {
    expect(assignLabels([], RULES)).toEqual([]);
  });
});

// TDD iteration 4 (RED): priority ordering when rules conflict.
// A more specific high-priority rule must suppress a broader low-priority
// rule *for the files it matches*, without affecting other files.
describe("assignLabels: priority resolves conflicts per file", () => {
  const conflicting: LabelRule[] = [
    { pattern: "docs/**", labels: ["documentation"] }, // default priority 0
    { pattern: "docs/api/**", labels: ["api-docs"], priority: 10 },
    { pattern: "src/**", labels: ["source"], priority: 1 },
    { pattern: "src/legacy/**", labels: ["legacy"], priority: 1 }, // tie → additive
  ];

  test("higher-priority rule wins for the files it matches", () => {
    expect(assignLabels(["docs/api/rest.md"], conflicting)).toEqual(["api-docs"]);
  });

  test("suppression is per file — other files still get the broad label", () => {
    expect(
      assignLabels(["docs/api/rest.md", "docs/intro.md"], conflicting),
    ).toEqual(["api-docs", "documentation"]);
  });

  test("rules tied on priority both contribute", () => {
    expect(assignLabels(["src/legacy/old.ts"], conflicting)).toEqual([
      "legacy",
      "source",
    ]);
  });
});

// TDD iteration 5 (RED): parsing + validation of untrusted JSON input.
// Errors must say *what* is wrong and *where* so a bad config is fixable
// from the CI log alone.
describe("parseRules: validates rule config JSON", () => {
  test("accepts a well-formed rules document", () => {
    const rules = parseRules(
      JSON.stringify({
        rules: [{ pattern: "docs/**", labels: ["documentation"], priority: 2 }],
      }),
    );
    expect(rules).toEqual([
      { pattern: "docs/**", labels: ["documentation"], priority: 2 },
    ]);
  });

  test("rejects malformed JSON with a helpful message", () => {
    expect(() => parseRules("{ not json")).toThrow(/not valid JSON/);
  });

  test("rejects a document without a top-level rules array", () => {
    expect(() => parseRules(JSON.stringify({ nope: [] }))).toThrow(
      /"rules" array/,
    );
  });

  test("rejects a rule missing its pattern, naming the rule index", () => {
    expect(() =>
      parseRules(JSON.stringify({ rules: [{ labels: ["x"] }] })),
    ).toThrow(/rules\[0\].*pattern/);
  });

  test("rejects a rule whose labels are missing or empty", () => {
    expect(() =>
      parseRules(JSON.stringify({ rules: [{ pattern: "a/**", labels: [] }] })),
    ).toThrow(/rules\[0\].*labels/);
  });

  test("rejects a non-numeric priority", () => {
    expect(() =>
      parseRules(
        JSON.stringify({
          rules: [{ pattern: "a/**", labels: ["x"], priority: "high" }],
        }),
      ),
    ).toThrow(/rules\[0\].*priority/);
  });
});

describe("parseChangedFiles: validates the mocked changed-file list", () => {
  test("accepts a JSON array of path strings", () => {
    expect(parseChangedFiles('["a.ts", "docs/b.md"]')).toEqual([
      "a.ts",
      "docs/b.md",
    ]);
  });

  test("rejects malformed JSON", () => {
    expect(() => parseChangedFiles("[oops")).toThrow(/not valid JSON/);
  });

  test("rejects non-array documents and non-string entries", () => {
    expect(() => parseChangedFiles('{"files": []}')).toThrow(/array/);
    expect(() => parseChangedFiles('["ok.ts", 42]')).toThrow(/\[1\].*string/);
  });
});
