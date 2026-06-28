// RED: First failing test. We drive out a glob matcher used by the label rules.
// We start at the smallest unit — matching a single path against a single glob —
// before building the higher-level label assignment logic on top of it.
import { describe, expect, test } from "bun:test";
import { matchGlob } from "./glob.ts";

describe("matchGlob", () => {
  test("literal path matches itself", () => {
    expect(matchGlob("README.md", "README.md")).toBe(true);
    expect(matchGlob("README.md", "LICENSE")).toBe(false);
  });

  test("single star matches within a segment but not across slashes", () => {
    expect(matchGlob("src/index.ts", "src/*.ts")).toBe(true);
    expect(matchGlob("src/utils/index.ts", "src/*.ts")).toBe(false);
  });

  test("question mark matches a single non-slash char", () => {
    expect(matchGlob("a.ts", "?.ts")).toBe(true);
    expect(matchGlob("ab.ts", "?.ts")).toBe(false);
  });

  test("double star matches across path segments", () => {
    expect(matchGlob("docs/guide.md", "docs/**")).toBe(true);
    expect(matchGlob("docs/a/b/c.md", "docs/**")).toBe(true);
    expect(matchGlob("docs", "docs/**")).toBe(true); // the dir itself
    expect(matchGlob("src/api/users.ts", "src/api/**")).toBe(true);
    expect(matchGlob("src/web/users.ts", "src/api/**")).toBe(false);
  });

  test("leading double-star matches any depth prefix", () => {
    expect(matchGlob("a/b/foo.test.ts", "**/*.test.*")).toBe(true);
    expect(matchGlob("foo.test.ts", "**/*.test.*")).toBe(true);
  });

  test("a slash-less pattern matches against the basename anywhere", () => {
    // "*.test.*" is given in the task as a tests rule; it should match a test
    // file at any depth, mirroring how labeler configs treat bare patterns.
    expect(matchGlob("src/components/Button.test.tsx", "*.test.*")).toBe(true);
    expect(matchGlob("button.test.js", "*.test.*")).toBe(true);
    expect(matchGlob("src/components/Button.tsx", "*.test.*")).toBe(false);
  });
});
