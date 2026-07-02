/**
 * TDD Cycle 1 (RED): glob pattern matching.
 *
 * Semantics (documented, minimatch-like):
 *   - `**` matches any number of characters INCLUDING `/`
 *   - `*`  matches any number of characters EXCEPT `/`
 *   - `?`  matches exactly one character except `/`
 *   - Patterns containing no `/` are matched against the file's basename
 *     (so `*.test.*` matches `src/foo.test.ts`), matching GitHub-labeler-style
 *     ergonomics.
 */
import { describe, expect, test } from "bun:test";
import { matchesGlob } from "../src/label-assigner.ts";

describe("matchesGlob", () => {
  test("** matches across directory separators", () => {
    expect(matchesGlob("docs/**", "docs/guide/intro.md")).toBe(true);
    expect(matchesGlob("docs/**", "docs/readme.md")).toBe(true);
    expect(matchesGlob("docs/**", "src/docs.ts")).toBe(false);
  });

  test("* does not cross directory separators", () => {
    expect(matchesGlob("src/*.ts", "src/index.ts")).toBe(true);
    expect(matchesGlob("src/*.ts", "src/api/index.ts")).toBe(false);
  });

  test("? matches a single non-separator character", () => {
    expect(matchesGlob("file?.txt", "file1.txt")).toBe(true);
    expect(matchesGlob("file?.txt", "file12.txt")).toBe(false);
    expect(matchesGlob("a?c", "a/c")).toBe(false);
  });

  test("patterns without a slash match against the basename", () => {
    expect(matchesGlob("*.test.*", "src/utils/math.test.ts")).toBe(true);
    expect(matchesGlob("*.test.*", "math.test.ts")).toBe(true);
    expect(matchesGlob("*.test.*", "src/main.ts")).toBe(false);
  });

  test("regex metacharacters in patterns are escaped literally", () => {
    expect(matchesGlob("src/(v1)/a.ts", "src/(v1)/a.ts")).toBe(true);
    expect(matchesGlob("a.b", "aXb")).toBe(false); // `.` is literal, not regex any-char
  });
});
