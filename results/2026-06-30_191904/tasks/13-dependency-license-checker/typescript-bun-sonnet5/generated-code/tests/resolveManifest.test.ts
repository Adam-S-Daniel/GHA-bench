import { describe, expect, test } from "bun:test";
import { resolveManifestPath } from "../src/resolveManifest";

// RED: fails until src/resolveManifest.ts exports resolveManifestPath.
describe("resolveManifestPath", () => {
  test("returns the explicit path unchanged when one is given", () => {
    const path = resolveManifestPath("some/custom/manifest.json", [
      "tests/fixtures/pkg-sample/package.json",
    ]);

    expect(path).toBe("some/custom/manifest.json");
  });

  test("picks the first candidate that exists on disk when no explicit path is given", () => {
    const path = resolveManifestPath(undefined, [
      "tests/fixtures/does-not-exist/package.json",
      "tests/fixtures/pkg-sample/package.json",
      "tests/fixtures/req-sample/requirements.txt",
    ]);

    expect(path).toBe("tests/fixtures/pkg-sample/package.json");
  });

  test("throws a clear error when no candidate exists", () => {
    expect(() =>
      resolveManifestPath(undefined, ["tests/fixtures/nope-a.json", "tests/fixtures/nope-b.txt"]),
    ).toThrow(/no manifest found/i);
  });
});
