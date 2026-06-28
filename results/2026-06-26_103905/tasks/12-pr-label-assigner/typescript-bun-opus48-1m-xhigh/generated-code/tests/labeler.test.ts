import { describe, expect, test } from "bun:test";
import {
  assignLabels,
  matchesGlob,
  parseConfig,
  type LabelerConfig,
} from "../src/labeler.ts";

// ---------------------------------------------------------------------------
// RED step 1: the most fundamental unit is glob matching. A path-to-label
// labeler is only as good as its pattern matcher, so we pin its semantics
// first, before any rule-evaluation logic exists.
// ---------------------------------------------------------------------------
describe("matchesGlob", () => {
  test("'docs/**' matches any file under docs/", () => {
    expect(matchesGlob("docs/**", "docs/intro.md")).toBe(true);
    expect(matchesGlob("docs/**", "docs/guides/setup/install.md")).toBe(true);
  });

  test("'docs/**' does NOT match files outside docs/", () => {
    expect(matchesGlob("docs/**", "src/docs.ts")).toBe(false);
    expect(matchesGlob("docs/**", "README.md")).toBe(false);
  });

  test("nested directory prefix 'src/api/**' is directory-scoped", () => {
    expect(matchesGlob("src/api/**", "src/api/users.ts")).toBe(true);
    expect(matchesGlob("src/api/**", "src/api/v2/orders.ts")).toBe(true);
    // A sibling directory must not match.
    expect(matchesGlob("src/api/**", "src/web/users.ts")).toBe(false);
  });

  test("slash-less pattern '*.test.*' matches the basename at any depth", () => {
    expect(matchesGlob("*.test.*", "foo.test.ts")).toBe(true);
    expect(matchesGlob("*.test.*", "src/components/Button.test.tsx")).toBe(true);
    // A non-test file must not match.
    expect(matchesGlob("*.test.*", "src/components/Button.tsx")).toBe(false);
  });

  test("single '*' does not cross directory boundaries", () => {
    expect(matchesGlob("src/*.ts", "src/index.ts")).toBe(true);
    expect(matchesGlob("src/*.ts", "src/api/index.ts")).toBe(false);
  });

  test("leading globstar '**/*.yml' matches at root and nested", () => {
    expect(matchesGlob("**/*.yml", "ci.yml")).toBe(true);
    expect(matchesGlob("**/*.yml", ".github/workflows/ci.yml")).toBe(true);
    expect(matchesGlob("**/*.yml", "ci.yaml")).toBe(false);
  });

  test("'?' matches exactly one non-slash character", () => {
    expect(matchesGlob("file?.txt", "file1.txt")).toBe(true);
    expect(matchesGlob("file?.txt", "file12.txt")).toBe(false);
  });

  test("regex metacharacters in patterns are treated literally", () => {
    // The '.' must be a literal dot, not "any char".
    expect(matchesGlob("a.b", "axb")).toBe(false);
    expect(matchesGlob("a.b", "a.b")).toBe(true);
  });

  test("an empty pattern never matches", () => {
    expect(matchesGlob("", "anything")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// RED step 2: rule evaluation. assignLabels() takes a validated config + a
// list of changed file paths and returns the final label set.
// ---------------------------------------------------------------------------
const SAMPLE_CONFIG: LabelerConfig = {
  rules: [
    { label: "documentation", patterns: ["docs/**", "*.md"], priority: 1 },
    { label: "api", patterns: ["src/api/**"], priority: 10 },
    { label: "tests", patterns: ["*.test.*", "**/*.spec.ts"], priority: 5 },
    { label: "ci", patterns: [".github/**"], priority: 8 },
  ],
};

describe("assignLabels", () => {
  test("a single matching file produces its rule's label", () => {
    const result = assignLabels(SAMPLE_CONFIG, ["docs/intro.md"]);
    expect(result.labels).toEqual(["documentation"]);
  });

  test("no matching files produces an empty label set", () => {
    const result = assignLabels(SAMPLE_CONFIG, ["src/web/widget.ts"]);
    expect(result.labels).toEqual([]);
  });

  test("a single file can produce MULTIPLE labels", () => {
    // README.md under docs would be documentation; here a test doc:
    const result = assignLabels(SAMPLE_CONFIG, ["src/api/client.test.ts"]);
    // Matches src/api/** (api) and *.test.* (tests).
    expect(new Set(result.labels)).toEqual(new Set(["api", "tests"]));
  });

  test("labels are the UNION across all changed files, deduplicated", () => {
    const result = assignLabels(SAMPLE_CONFIG, [
      "docs/a.md",
      "docs/b.md", // duplicate label source — must not duplicate
      "src/api/users.ts",
    ]);
    expect(new Set(result.labels)).toEqual(new Set(["documentation", "api"]));
    // No label appears twice.
    expect(result.labels.length).toBe(new Set(result.labels).size);
  });

  test("PRIORITY controls output ordering (higher priority first)", () => {
    const result = assignLabels(SAMPLE_CONFIG, [
      "docs/intro.md", // documentation, priority 1
      "src/api/users.ts", // api, priority 10
      "src/util.test.ts", // tests, priority 5
      ".github/workflows/ci.yml", // ci, priority 8
    ]);
    // Expected order by descending priority: api(10), ci(8), tests(5), documentation(1)
    expect(result.labels).toEqual(["api", "ci", "tests", "documentation"]);
  });

  test("priority ties fall back to declaration order (stable)", () => {
    const config: LabelerConfig = {
      rules: [
        { label: "first", patterns: ["a/**"] }, // priority defaults to 0
        { label: "second", patterns: ["b/**"] }, // priority defaults to 0
      ],
    };
    const result = assignLabels(config, ["b/x.ts", "a/y.ts"]);
    expect(result.labels).toEqual(["first", "second"]);
  });

  test("the matches map records which files triggered each label", () => {
    const result = assignLabels(SAMPLE_CONFIG, [
      "docs/a.md",
      "src/api/users.ts",
      "src/api/orders.ts",
    ]);
    expect(result.matches.documentation).toEqual(["docs/a.md"]);
    expect(result.matches.api).toEqual(["src/api/orders.ts", "src/api/users.ts"]);
  });
});

// ---------------------------------------------------------------------------
// RED step 3: configuration parsing & validation. parseConfig() turns
// untrusted JSON into a validated LabelerConfig, throwing meaningful errors.
// ---------------------------------------------------------------------------
describe("parseConfig", () => {
  test("accepts a well-formed { rules: [...] } object", () => {
    const config = parseConfig({
      rules: [{ label: "docs", patterns: ["docs/**"] }],
    });
    expect(config.rules.length).toBe(1);
    expect(config.rules[0]!.priority).toBe(0); // default applied
  });

  test("accepts a bare top-level array of rules", () => {
    const config = parseConfig([{ label: "docs", patterns: ["docs/**"] }]);
    expect(config.rules.length).toBe(1);
  });

  test("rejects a non-object / non-array config", () => {
    expect(() => parseConfig("nope")).toThrow(/config/i);
  });

  test("rejects a rule missing a label", () => {
    expect(() => parseConfig({ rules: [{ patterns: ["x"] }] })).toThrow(/label/i);
  });

  test("rejects a rule whose patterns is not a non-empty string array", () => {
    expect(() => parseConfig({ rules: [{ label: "x", patterns: [] }] })).toThrow(
      /pattern/i,
    );
    expect(() =>
      parseConfig({ rules: [{ label: "x", patterns: "docs/**" }] }),
    ).toThrow(/pattern/i);
  });

  test("rejects a non-numeric priority", () => {
    expect(() =>
      parseConfig({ rules: [{ label: "x", patterns: ["y"], priority: "high" }] }),
    ).toThrow(/priority/i);
  });
});
