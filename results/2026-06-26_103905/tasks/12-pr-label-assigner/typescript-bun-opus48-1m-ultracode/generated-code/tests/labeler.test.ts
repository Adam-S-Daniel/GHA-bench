// Unit tests for the PR label assigner core logic.
//
// Written red/green TDD-style: each `describe` block was added as a failing
// test first, then the minimum implementation was written to make it pass.
//
// These are FAST, hermetic tests with no I/O against the live filesystem
// except for tightly-scoped temp files in the config-loading section. They are
// the suite that runs via `bun test`. The end-to-end pipeline (GitHub Actions
// via `act`) is exercised separately by `act-runner.ts`.

import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  matchPattern,
  assignLabels,
  validateConfig,
  loadConfig,
  loadChangedFiles,
  type LabelerConfig,
} from "../src/labeler.ts";

describe("matchPattern (glob matching)", () => {
  test("matches a recursive directory pattern against nested files", () => {
    expect(matchPattern("docs/**", "docs/readme.md")).toBe(true);
    expect(matchPattern("docs/**", "docs/guide/intro.md")).toBe(true);
  });

  test("does not match files outside the directory pattern", () => {
    expect(matchPattern("docs/**", "src/index.ts")).toBe(false);
    expect(matchPattern("src/api/**", "src/web/app.ts")).toBe(false);
  });

  test("matches a nested api path", () => {
    expect(matchPattern("src/api/**", "src/api/v1/users.ts")).toBe(true);
  });

  test("a basename-style pattern (no slash) matches files in any directory", () => {
    // The task's example rule `*.test.* -> tests` should label a test file
    // wherever it lives, so a slash-free pattern falls back to basename matching.
    expect(matchPattern("*.test.*", "foo.test.ts")).toBe(true);
    expect(matchPattern("*.test.*", "src/components/foo.test.tsx")).toBe(true);
    expect(matchPattern("*.md", "docs/changelog.md")).toBe(true);
  });

  test("a slash-free pattern still rejects non-matching basenames", () => {
    expect(matchPattern("*.test.*", "src/foo.ts")).toBe(false);
    expect(matchPattern("*.md", "src/index.ts")).toBe(false);
  });

  test("a pattern containing a slash is anchored to the full path only", () => {
    // `src/*.ts` must NOT match a deeper file, and must not fall back to basename.
    expect(matchPattern("src/*.ts", "src/index.ts")).toBe(true);
    expect(matchPattern("src/*.ts", "src/api/index.ts")).toBe(false);
    expect(matchPattern("src/*.ts", "index.ts")).toBe(false);
  });

  test("an invalid glob pattern throws a descriptive error", () => {
    // Empty patterns are meaningless and must be rejected loudly.
    expect(() => matchPattern("", "anything")).toThrow(/pattern/i);
  });
});

describe("assignLabels (rule application)", () => {
  const config: LabelerConfig = {
    rules: [
      { label: "documentation", patterns: ["docs/**", "*.md"] },
      { label: "api", patterns: ["src/api/**"], priority: 10 },
      { label: "tests", patterns: ["*.test.*"] },
      { label: "frontend", patterns: ["src/web/**"] },
    ],
  };

  test("assigns a single label when one rule matches", () => {
    const result = assignLabels(["docs/readme.md"], config);
    expect(result.labels).toEqual(["documentation"]);
  });

  test("assigns multiple labels to a PR across different files", () => {
    const result = assignLabels(
      ["docs/readme.md", "src/api/users.ts", "src/web/app.test.tsx"],
      config,
    );
    // Sorted by priority desc, then name asc: api(10), then documentation/frontend/tests(0).
    expect(result.labels).toEqual(["api", "documentation", "frontend", "tests"]);
  });

  test("a single file can receive multiple labels", () => {
    // `src/api/client.test.ts` matches both the api rule and the tests rule.
    const result = assignLabels(["src/api/client.test.ts"], config);
    expect(result.labels).toEqual(["api", "tests"]);
    expect(result.byFile["src/api/client.test.ts"]).toEqual(["api", "tests"]);
  });

  test("labels are de-duplicated across multiple matching files", () => {
    const result = assignLabels(["docs/a.md", "docs/b.md", "README.md"], config);
    expect(result.labels).toEqual(["documentation"]);
  });

  test("orders the final label set by priority (descending) then name", () => {
    const ordered: LabelerConfig = {
      rules: [
        { label: "low", patterns: ["a.txt"], priority: 1 },
        { label: "high", patterns: ["b.txt"], priority: 100 },
        { label: "mid", patterns: ["c.txt"], priority: 50 },
      ],
    };
    const result = assignLabels(["a.txt", "b.txt", "c.txt"], ordered);
    expect(result.labels).toEqual(["high", "mid", "low"]);
  });

  test("returns an empty label set when nothing matches", () => {
    const result = assignLabels(["LICENSE", "Makefile"], config);
    expect(result.labels).toEqual([]);
    expect(result.byFile).toEqual({ LICENSE: [], Makefile: [] });
  });

  describe("conflict resolution via mutually-exclusive groups", () => {
    // A file that is both 'critical' and 'normal' size should only get the
    // higher-priority label because they share an exclusive group.
    const sized: LabelerConfig = {
      rules: [
        { label: "size/large", patterns: ["**"], group: "size", priority: 1 },
        { label: "size/api", patterns: ["src/api/**"], group: "size", priority: 100 },
      ],
    };

    test("only the highest-priority rule in a group wins for a given file", () => {
      const result = assignLabels(["src/api/users.ts"], sized);
      // Both match, but they share group 'size'; api priority(100) beats large(1).
      expect(result.labels).toEqual(["size/api"]);
      expect(result.byFile["src/api/users.ts"]).toEqual(["size/api"]);
    });

    test("the fallback group label still applies to non-conflicting files", () => {
      const result = assignLabels(["README.md"], sized);
      expect(result.labels).toEqual(["size/large"]);
    });

    test("group conflicts are resolved per-file, not globally", () => {
      const result = assignLabels(["src/api/users.ts", "README.md"], sized);
      // api wins for the api file; large wins for the readme. Both appear.
      expect(result.labels).toEqual(["size/api", "size/large"]);
    });
  });
});

describe("validateConfig (schema validation & error messages)", () => {
  test("accepts a well-formed config and returns a typed object", () => {
    const raw = { rules: [{ label: "docs", patterns: ["docs/**"], priority: 2 }] };
    const config = validateConfig(raw);
    expect(config.rules).toHaveLength(1);
    expect(config.rules[0]!.label).toBe("docs");
  });

  test("rejects a non-object config", () => {
    expect(() => validateConfig(null)).toThrow(/config must be an object/i);
    expect(() => validateConfig(42)).toThrow(/config must be an object/i);
  });

  test("rejects a config without a rules array", () => {
    expect(() => validateConfig({})).toThrow(/"rules" array/i);
    expect(() => validateConfig({ rules: "nope" })).toThrow(/"rules" array/i);
  });

  test("rejects a rule missing a label", () => {
    expect(() => validateConfig({ rules: [{ patterns: ["x"] }] })).toThrow(
      /rule at index 0.*non-empty "label"/i,
    );
  });

  test("rejects a rule missing patterns", () => {
    expect(() => validateConfig({ rules: [{ label: "x" }] })).toThrow(
      /rule "x".*non-empty "patterns"/i,
    );
  });

  test("rejects a rule whose patterns contain a non-string", () => {
    expect(() => validateConfig({ rules: [{ label: "x", patterns: [3] }] })).toThrow(
      /rule "x".*pattern.*string/i,
    );
  });

  test("rejects a non-numeric priority", () => {
    expect(() =>
      validateConfig({ rules: [{ label: "x", patterns: ["a"], priority: "high" }] }),
    ).toThrow(/rule "x".*priority.*number/i);
  });
});

describe("file loading (graceful I/O errors)", () => {
  const dir = mkdtempSync(join(tmpdir(), "labeler-test-"));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  test("loadConfig reads and validates a JSON config file", () => {
    const path = join(dir, "good.json");
    writeFileSync(path, JSON.stringify({ rules: [{ label: "a", patterns: ["*.a"] }] }));
    const config = loadConfig(path);
    expect(config.rules[0]!.label).toBe("a");
  });

  test("loadConfig gives a clear error when the file is missing", () => {
    expect(() => loadConfig(join(dir, "does-not-exist.json"))).toThrow(
      /config file not found/i,
    );
  });

  test("loadConfig gives a clear error on malformed JSON", () => {
    const path = join(dir, "bad.json");
    writeFileSync(path, "{ this is not json");
    expect(() => loadConfig(path)).toThrow(/invalid json/i);
  });

  test("loadChangedFiles parses one path per line, trimming blanks & comments", () => {
    const path = join(dir, "files.txt");
    writeFileSync(path, "docs/a.md\n\n  src/api/x.ts  \n# a comment\nREADME.md\n");
    expect(loadChangedFiles(path)).toEqual(["docs/a.md", "src/api/x.ts", "README.md"]);
  });

  test("loadChangedFiles errors clearly when the file is missing", () => {
    expect(() => loadChangedFiles(join(dir, "nope.txt"))).toThrow(
      /changed-files list not found/i,
    );
  });
});
