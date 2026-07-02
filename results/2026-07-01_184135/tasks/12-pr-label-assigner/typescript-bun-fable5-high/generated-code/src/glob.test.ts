// TDD iteration 1 (RED): glob matching — the primitive every labeling rule
// is built on. We support the subset of glob syntax used by GitHub's own
// labeler configs:
//   **  matches any number of path segments (including zero)
//   *   matches anything within one segment (never crosses "/")
//   ?   matches a single character within a segment
// Convention (gitignore-style): a pattern with no "/" matches against the
// file's basename, so "*.test.*" matches "src/app.test.ts" anywhere in the tree.
import { describe, expect, test } from "bun:test";
import { matchesGlob } from "./glob";

describe("matchesGlob: ** (directory subtree patterns)", () => {
  test("docs/** matches files directly under docs/", () => {
    expect(matchesGlob("docs/**", "docs/readme.md")).toBe(true);
  });

  test("docs/** matches deeply nested files", () => {
    expect(matchesGlob("docs/**", "docs/guides/api/auth.md")).toBe(true);
  });

  test("docs/** does not match files outside docs/", () => {
    expect(matchesGlob("docs/**", "src/docs.ts")).toBe(false);
    expect(matchesGlob("docs/**", "documentation/readme.md")).toBe(false);
  });

  test("src/**/*.ts matches at any depth, including zero directories", () => {
    expect(matchesGlob("src/**/*.ts", "src/index.ts")).toBe(true);
    expect(matchesGlob("src/**/*.ts", "src/api/v2/users.ts")).toBe(true);
    expect(matchesGlob("src/**/*.ts", "src/style.css")).toBe(false);
  });
});

// TDD iteration 2 (RED): basename matching, single-segment wildcards, and
// literal-character safety (dots in globs must not act as regex wildcards).
describe("matchesGlob: basename patterns and single-segment wildcards", () => {
  test("*.test.* (no slash) matches against the basename at any depth", () => {
    expect(matchesGlob("*.test.*", "app.test.ts")).toBe(true);
    expect(matchesGlob("*.test.*", "src/deep/nested/app.test.ts")).toBe(true);
    expect(matchesGlob("*.test.*", "src/app.ts")).toBe(false);
  });

  test("* does not cross directory boundaries when the pattern has a slash", () => {
    expect(matchesGlob("src/*.ts", "src/index.ts")).toBe(true);
    expect(matchesGlob("src/*.ts", "src/api/users.ts")).toBe(false);
  });

  test("? matches exactly one non-separator character", () => {
    expect(matchesGlob("v?/data.json", "v1/data.json")).toBe(true);
    expect(matchesGlob("v?/data.json", "v12/data.json")).toBe(false);
  });

  test("dots are literal — *.ts must not match *-ts via regex-dot leakage", () => {
    expect(matchesGlob("*.ts", "index-ts")).toBe(false);
    expect(matchesGlob("Makefile", "Makefile")).toBe(true);
    expect(matchesGlob("Makefile", "Makefile2")).toBe(false);
  });
});
