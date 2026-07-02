import { describe, expect, test } from "bun:test";
import { matchGlob } from "./glob";

// RED: first failing test. matchGlob does not exist yet.
describe("matchGlob", () => {
  test("matches an exact literal path", () => {
    expect(matchGlob("README.md", "README.md")).toBe(true);
  });

  test("does not match a different literal path", () => {
    expect(matchGlob("README.md", "OTHER.md")).toBe(false);
  });

  test("`**` matches nested directories of any depth", () => {
    expect(matchGlob("docs/**", "docs/guide/setup.md")).toBe(true);
    expect(matchGlob("docs/**", "docs/readme.md")).toBe(true);
  });

  test("`**` does not match paths outside the prefix", () => {
    expect(matchGlob("docs/**", "src/docs/readme.md")).toBe(false);
  });

  test("`*` does not cross directory separators", () => {
    expect(matchGlob("src/api/*", "src/api/routes.ts")).toBe(true);
    expect(matchGlob("src/api/*", "src/api/v1/routes.ts")).toBe(false);
  });

  test("`src/api/**` matches deeply nested files", () => {
    expect(matchGlob("src/api/**", "src/api/v1/users/handler.ts")).toBe(true);
  });

  test("`*.test.*` matches test files regardless of extension", () => {
    expect(matchGlob("*.test.*", "foo.test.ts")).toBe(true);
    expect(matchGlob("*.test.*", "foo.test.js")).toBe(true);
    expect(matchGlob("*.test.*", "foo.spec.ts")).toBe(false);
  });

  test("`**/*.test.*` matches test files at any depth", () => {
    expect(matchGlob("**/*.test.*", "src/utils/math.test.ts")).toBe(true);
    expect(matchGlob("**/*.test.*", "math.test.ts")).toBe(true);
  });

  test("a slash-free pattern matches against the basename at any depth", () => {
    expect(matchGlob("*.test.*", "src/api/routes.test.ts")).toBe(true);
    expect(matchGlob("*.test.*", "routes.test.ts")).toBe(true);
    expect(matchGlob("*.test.*", "src/api/routes.spec.ts")).toBe(false);
  });
});
