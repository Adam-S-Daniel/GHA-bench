/**
 * Tests for the environment matrix generator.
 *
 * TDD approach: each `describe` block below was written as a failing test
 * FIRST (red), then the minimum implementation was added in src/matrix.ts
 * to make it pass (green), followed by refactoring. Cycles, in order:
 *
 *   1. Basic cartesian expansion (os x version x feature)
 *   2. Strategy output shape (fail-fast, max-parallel defaults & overrides)
 *   3. Exclude rules (partial-match removal, GHA semantics)
 *   4. Include rules (extend matching combos / append new combos)
 *   5. Validation errors (empty dimensions, bad max-parallel, max-size cap)
 */
import { describe, expect, test } from "bun:test";
import { generateMatrix, MatrixError } from "../src/matrix";
import type { MatrixConfig } from "../src/matrix";

/** Fixture helper: a minimal valid config that tests can override. */
function baseConfig(overrides: Partial<MatrixConfig> = {}): MatrixConfig {
  return {
    os: ["ubuntu-latest", "macos-latest"],
    versions: ["18", "20"],
    features: ["stable"],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Cycle 1: basic cartesian expansion
// ---------------------------------------------------------------------------
describe("basic matrix expansion", () => {
  test("expands os x versions x features into all combinations", () => {
    const result = generateMatrix(baseConfig());
    expect(result.count).toBe(4);
    expect(result.combinations).toEqual([
      { os: "ubuntu-latest", version: "18", feature: "stable" },
      { os: "ubuntu-latest", version: "20", feature: "stable" },
      { os: "macos-latest", version: "18", feature: "stable" },
      { os: "macos-latest", version: "20", feature: "stable" },
    ]);
  });

  test("carries the raw dimensions through to strategy.matrix", () => {
    const result = generateMatrix(baseConfig());
    expect(result.strategy.matrix.os).toEqual(["ubuntu-latest", "macos-latest"]);
    expect(result.strategy.matrix.version).toEqual(["18", "20"]);
    expect(result.strategy.matrix.feature).toEqual(["stable"]);
  });
});

// ---------------------------------------------------------------------------
// Cycle 2: strategy output shape (fail-fast / max-parallel)
// ---------------------------------------------------------------------------
describe("strategy configuration", () => {
  test("defaults: fail-fast true, no max-parallel key", () => {
    const result = generateMatrix(baseConfig());
    expect(result.strategy["fail-fast"]).toBe(true);
    expect("max-parallel" in result.strategy).toBe(false);
  });

  test("honours explicit fail-fast=false and max-parallel", () => {
    const result = generateMatrix(
      baseConfig({ "fail-fast": false, "max-parallel": 2 }),
    );
    expect(result.strategy["fail-fast"]).toBe(false);
    expect(result.strategy["max-parallel"]).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// Cycle 3: exclude rules
// ---------------------------------------------------------------------------
describe("exclude rules", () => {
  test("removes combinations matching ALL keys of an exclude entry", () => {
    const result = generateMatrix(
      baseConfig({ exclude: [{ os: "macos-latest", version: "18" }] }),
    );
    expect(result.count).toBe(3);
    expect(result.combinations).toEqual([
      { os: "ubuntu-latest", version: "18", feature: "stable" },
      { os: "ubuntu-latest", version: "20", feature: "stable" },
      { os: "macos-latest", version: "20", feature: "stable" },
    ]);
    // exclude entries are also passed through for GHA to consume natively
    expect(result.strategy.matrix.exclude).toEqual([
      { os: "macos-latest", version: "18" },
    ]);
  });

  test("a partial exclude removes every combination it matches", () => {
    const result = generateMatrix(
      baseConfig({ exclude: [{ os: "macos-latest" }] }),
    );
    expect(result.count).toBe(2);
    expect(result.combinations.every((c) => c.os === "ubuntu-latest")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Cycle 4: include rules
// ---------------------------------------------------------------------------
describe("include rules", () => {
  test("an include matching existing combos extends them with extra keys", () => {
    const result = generateMatrix(
      baseConfig({ include: [{ os: "ubuntu-latest", experimental: "true" }] }),
    );
    // No new combos: both ubuntu combos gain `experimental`
    expect(result.count).toBe(4);
    const ubuntu = result.combinations.filter((c) => c.os === "ubuntu-latest");
    expect(ubuntu.every((c) => c.experimental === "true")).toBe(true);
    const macos = result.combinations.filter((c) => c.os === "macos-latest");
    expect(macos.every((c) => !("experimental" in c))).toBe(true);
  });

  test("an include matching no combos is appended as a new combination", () => {
    const result = generateMatrix(
      baseConfig({
        include: [{ os: "windows-latest", version: "22", feature: "beta" }],
      }),
    );
    expect(result.count).toBe(5);
    expect(result.combinations[4]).toEqual({
      os: "windows-latest",
      version: "22",
      feature: "beta",
    });
  });

  test("includes are applied AFTER excludes (GHA order)", () => {
    const result = generateMatrix(
      baseConfig({
        exclude: [{ os: "macos-latest", version: "18" }],
        include: [{ os: "macos-latest", version: "18", feature: "readded" }],
      }),
    );
    // The excluded combo differs in `feature`, so the include appends anew.
    expect(result.count).toBe(4);
    expect(result.combinations).toContainEqual({
      os: "macos-latest",
      version: "18",
      feature: "readded",
    });
  });
});

// ---------------------------------------------------------------------------
// Cycle 5: validation & error handling
// ---------------------------------------------------------------------------
describe("validation", () => {
  test("rejects an empty os dimension with a meaningful message", () => {
    expect(() => generateMatrix(baseConfig({ os: [] }))).toThrow(
      new MatrixError('Dimension "os" must be a non-empty array of strings'),
    );
  });

  test("rejects a missing dimension", () => {
    const cfg = { os: ["ubuntu-latest"], features: ["x"] } as MatrixConfig;
    expect(() => generateMatrix(cfg)).toThrow(
      'Dimension "versions" must be a non-empty array of strings',
    );
  });

  test("rejects max-parallel < 1", () => {
    expect(() => generateMatrix(baseConfig({ "max-parallel": 0 }))).toThrow(
      '"max-parallel" must be a positive integer, got 0',
    );
  });

  test("rejects a matrix larger than max-size", () => {
    expect(() => generateMatrix(baseConfig({ "max-size": 3 }))).toThrow(
      "Matrix size 4 exceeds maximum allowed size 3",
    );
  });

  test("enforces the GitHub Actions hard limit of 256 by default", () => {
    const cfg = baseConfig({
      os: Array.from({ length: 8 }, (_, i) => `os${i}`),
      versions: Array.from({ length: 8 }, (_, i) => `v${i}`),
      features: Array.from({ length: 5 }, (_, i) => `f${i}`),
    });
    expect(() => generateMatrix(cfg)).toThrow(
      "Matrix size 320 exceeds maximum allowed size 256",
    );
  });

  test("size is validated AFTER include/exclude are applied", () => {
    // 4 base combos, max-size 3 — but excluding two brings it to 2: valid.
    const result = generateMatrix(
      baseConfig({ "max-size": 3, exclude: [{ os: "macos-latest" }] }),
    );
    expect(result.count).toBe(2);
  });
});
