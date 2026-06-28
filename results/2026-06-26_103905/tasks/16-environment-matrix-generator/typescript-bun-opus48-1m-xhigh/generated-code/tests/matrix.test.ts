import { describe, expect, test } from "bun:test";
import {
  applyExclude,
  applyInclude,
  cartesianProduct,
  generateMatrix,
  parseConfig,
} from "../src/matrix.ts";
import type { MatrixConfig } from "../src/types.ts";

// ---------------------------------------------------------------------------
// TDD cycle 1 — cartesian product of the matrix axes.
//
// A GitHub Actions matrix is the cartesian product of its axes. Before we can
// apply include/exclude rules we must be able to expand the axes themselves.
// The product must keep a stable, predictable order: the FIRST declared axis
// varies slowest and the LAST declared axis varies fastest. GitHub relies on
// this order, so we lock it down with a test.
// ---------------------------------------------------------------------------
describe("cartesianProduct", () => {
  test("expands two axes with the first axis varying slowest", () => {
    const combos = cartesianProduct({
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
    });

    expect(combos).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "18" },
      { os: "windows-latest", node: "20" },
    ]);
  });

  test("expands three axes (os x language x feature)", () => {
    const combos = cartesianProduct({
      os: ["ubuntu-latest"],
      node: ["18", "20"],
      feature: ["default", "experimental"],
    });

    expect(combos).toEqual([
      { os: "ubuntu-latest", node: "18", feature: "default" },
      { os: "ubuntu-latest", node: "18", feature: "experimental" },
      { os: "ubuntu-latest", node: "20", feature: "default" },
      { os: "ubuntu-latest", node: "20", feature: "experimental" },
    ]);
  });

  test("a single axis yields one combination per value", () => {
    expect(cartesianProduct({ os: ["ubuntu-latest", "macos-latest"] })).toEqual([
      { os: "ubuntu-latest" },
      { os: "macos-latest" },
    ]);
  });

  test("no axes yields a single empty combination", () => {
    // The empty product is one empty tuple — important so that a config that
    // only supplies `include` entries still has a base to attach them to.
    expect(cartesianProduct({})).toEqual([{}]);
  });

  test("preserves non-string scalar values (numbers / booleans)", () => {
    expect(
      cartesianProduct({ node: [18, 20], experimental: [true, false] }),
    ).toEqual([
      { node: 18, experimental: true },
      { node: 18, experimental: false },
      { node: 20, experimental: true },
      { node: 20, experimental: false },
    ]);
  });
});

// ---------------------------------------------------------------------------
// TDD cycle 2 — exclude rules.
//
// GitHub `exclude` entries are PARTIAL filters: an entry removes every
// combination in which all of the entry's key:value pairs are present and
// equal. An exclude entry may name a subset of the axes (e.g. just `os`), in
// which case it removes every combination on that OS.
// ---------------------------------------------------------------------------
describe("applyExclude", () => {
  const base = cartesianProduct({
    os: ["ubuntu-latest", "windows-latest"],
    node: ["18", "20"],
  });

  test("removes the single fully-specified combination that matches", () => {
    const result = applyExclude(base, [{ os: "windows-latest", node: "18" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "20" },
    ]);
  });

  test("a partial exclude removes every combination it matches", () => {
    // Exclude all of windows -> both windows rows disappear.
    const result = applyExclude(base, [{ os: "windows-latest" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
    ]);
  });

  test("multiple exclude entries are all applied", () => {
    const result = applyExclude(base, [
      { node: "18" },
      { os: "windows-latest" },
    ]);
    expect(result).toEqual([{ os: "ubuntu-latest", node: "20" }]);
  });

  test("an exclude that matches nothing leaves the matrix untouched", () => {
    const result = applyExclude(base, [{ os: "macos-latest" }]);
    expect(result).toEqual(base);
  });

  test("no exclude entries is a no-op", () => {
    expect(applyExclude(base, [])).toEqual(base);
  });
});

// ---------------------------------------------------------------------------
// TDD cycle 3 — include rules (the subtle one).
//
// GitHub `include` has precise, documented semantics:
//   * Each include entry tries to EXTEND existing *base* combinations. It can
//     extend a base combination only when the keys it shares with the original
//     matrix axes all match that combination. Keys it adds that are NOT axes
//     (e.g. an extra "color") are merged in, and may be overwritten by later
//     include entries.
//   * Include entries only merge into the ORIGINAL base combinations, never
//     into combinations created by a previous include entry.
//   * If an include entry matches no base combination, it becomes a brand-new
//     standalone combination.
//
// We pin the behaviour to GitHub's own canonical documentation example, whose
// expected output is published, so we know our implementation is faithful.
// ---------------------------------------------------------------------------
describe("applyInclude", () => {
  test("matches GitHub's documented fruit/animal example exactly", () => {
    const base = cartesianProduct({
      fruit: ["apple", "pear"],
      animal: ["cat", "dog"],
    });
    const matrixKeys = ["fruit", "animal"];
    const includes = [
      { color: "green" },
      { color: "pink", animal: "cat" },
      { fruit: "apple", shape: "circle" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ];

    expect(applyInclude(base, includes, matrixKeys)).toEqual([
      { fruit: "apple", animal: "cat", color: "pink", shape: "circle" },
      { fruit: "apple", animal: "dog", color: "green", shape: "circle" },
      { fruit: "pear", animal: "cat", color: "pink" },
      { fruit: "pear", animal: "dog", color: "green" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ]);
  });

  test("an include with only non-axis keys is added to every combination", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest", "macos-latest"] });
    expect(applyInclude(base, [{ coverage: true }], ["os"])).toEqual([
      { os: "ubuntu-latest", coverage: true },
      { os: "macos-latest", coverage: true },
    ]);
  });

  test("an include scoped to one axis value extends only the matching rows", () => {
    const base = cartesianProduct({
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
    });
    // Add `experimental: true` only to the windows rows.
    expect(
      applyInclude(base, [{ os: "windows-latest", experimental: true }], [
        "os",
        "node",
      ]),
    ).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "18", experimental: true },
      { os: "windows-latest", node: "20", experimental: true },
    ]);
  });

  test("an unmatched include becomes a new standalone combination", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest"] });
    expect(
      applyInclude(base, [{ os: "macos-latest", node: "22" }], ["os"]),
    ).toEqual([
      { os: "ubuntu-latest" },
      { os: "macos-latest", node: "22" },
    ]);
  });

  test("no include entries is a no-op (returns a copy of the base)", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest"] });
    expect(applyInclude(base, [], ["os"])).toEqual(base);
  });
});

// ---------------------------------------------------------------------------
// TDD cycle 4 — end-to-end matrix generation (exclude THEN include, plus the
// strategy metadata and the max-size safety valve).
//
// GitHub processes the matrix in a fixed order: expand the axes, apply
// `exclude`, then apply `include` (which is why include can re-add an excluded
// combination). `generateMatrix` wires the pure helpers together in that order
// and packages the result as a ready-to-use strategy object.
// ---------------------------------------------------------------------------
describe("generateMatrix", () => {
  test("expands axes and packages a strategy object with metadata", () => {
    const config: MatrixConfig = {
      matrix: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
      maxParallel: 2,
      failFast: false,
    };

    expect(generateMatrix(config)).toEqual({
      matrix: {
        include: [
          { os: "ubuntu-latest", node: "18" },
          { os: "ubuntu-latest", node: "20" },
          { os: "windows-latest", node: "18" },
          { os: "windows-latest", node: "20" },
        ],
      },
      count: 4,
      "max-parallel": 2,
      "fail-fast": false,
    });
  });

  test("omits max-parallel and fail-fast when not configured", () => {
    const result = generateMatrix({ matrix: { os: ["ubuntu-latest"] } });
    expect(result).toEqual({
      matrix: { include: [{ os: "ubuntu-latest" }] },
      count: 1,
    });
    expect("max-parallel" in result).toBe(false);
    expect("fail-fast" in result).toBe(false);
  });

  test("applies exclude before include, so include can re-add an excluded row", () => {
    const result = generateMatrix({
      matrix: { os: ["ubuntu-latest", "windows-latest"], node: ["18", "20"] },
      exclude: [{ os: "windows-latest" }],
      // Re-add exactly one of the excluded combinations via include.
      include: [{ os: "windows-latest", node: "20" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", node: "18" },
      { os: "ubuntu-latest", node: "20" },
      { os: "windows-latest", node: "20" },
    ]);
    expect(result.count).toBe(3);
  });

  test("a feature-flag axis participates in the product", () => {
    const result = generateMatrix({
      matrix: {
        os: ["ubuntu-latest"],
        node: ["20"],
        feature: ["off", "on"],
      },
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", node: "20", feature: "off" },
      { os: "ubuntu-latest", node: "20", feature: "on" },
    ]);
  });

  test("passes when the matrix size is exactly at the max-size limit", () => {
    const result = generateMatrix({
      matrix: { os: ["ubuntu-latest", "windows-latest"], node: ["18", "20"] },
      maxSize: 4,
    });
    expect(result.count).toBe(4);
  });

  test("throws a meaningful error when the matrix exceeds max-size", () => {
    const config: MatrixConfig = {
      matrix: {
        os: ["ubuntu-latest", "windows-latest", "macos-latest"],
        node: ["16", "18", "20"],
      },
      maxSize: 4,
    };
    // 3 x 3 = 9 combinations, limit is 4.
    expect(() => generateMatrix(config)).toThrow(
      "Generated matrix has 9 combinations, which exceeds the configured maxSize of 4",
    );
  });
});

// ---------------------------------------------------------------------------
// TDD cycle 5 — config validation. The generator consumes untrusted JSON, so
// `parseConfig` narrows `unknown` into a `MatrixConfig` and rejects malformed
// input with actionable, human-readable error messages (requirement 5).
// ---------------------------------------------------------------------------
describe("parseConfig", () => {
  test("accepts and normalises a full, valid config", () => {
    const cfg = parseConfig({
      matrix: { os: ["ubuntu-latest"], node: [18, 20] },
      include: [{ os: "ubuntu-latest", node: 18, lint: true }],
      exclude: [{ node: 20 }],
      maxParallel: 3,
      failFast: false,
      maxSize: 10,
    });
    expect(cfg).toEqual({
      matrix: { os: ["ubuntu-latest"], node: [18, 20] },
      include: [{ os: "ubuntu-latest", node: 18, lint: true }],
      exclude: [{ node: 20 }],
      maxParallel: 3,
      failFast: false,
      maxSize: 10,
    });
  });

  test("defaults the optional fields sensibly when omitted", () => {
    const cfg = parseConfig({ matrix: { os: ["ubuntu-latest"] } });
    expect(cfg.matrix).toEqual({ os: ["ubuntu-latest"] });
    expect(cfg.include).toBeUndefined();
    expect(cfg.exclude).toBeUndefined();
    expect(cfg.maxParallel).toBeUndefined();
    expect(cfg.failFast).toBeUndefined();
    expect(cfg.maxSize).toBeUndefined();
  });

  test("rejects a non-object configuration", () => {
    expect(() => parseConfig(null)).toThrow(
      "Configuration must be a JSON object",
    );
    expect(() => parseConfig([1, 2, 3])).toThrow(
      "Configuration must be a JSON object",
    );
    expect(() => parseConfig("nope")).toThrow(
      "Configuration must be a JSON object",
    );
  });

  test("requires a non-empty `matrix` object", () => {
    expect(() => parseConfig({})).toThrow(
      'Configuration is missing the required "matrix" object',
    );
    expect(() => parseConfig({ matrix: {} })).toThrow(
      'The "matrix" object must declare at least one axis',
    );
  });

  test("requires each axis to be a non-empty array of scalars", () => {
    expect(() => parseConfig({ matrix: { os: "ubuntu-latest" } })).toThrow(
      'Matrix axis "os" must be a non-empty array',
    );
    expect(() => parseConfig({ matrix: { os: [] } })).toThrow(
      'Matrix axis "os" must be a non-empty array',
    );
    expect(() =>
      parseConfig({ matrix: { os: [{ not: "scalar" }] } }),
    ).toThrow('Matrix axis "os" contains a non-scalar value');
  });

  test("rejects include/exclude that are not arrays of objects", () => {
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, include: {} }),
    ).toThrow('"include" must be an array');
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, exclude: [42] }),
    ).toThrow('"exclude" entry at index 0 must be an object');
  });

  test("rejects a non-positive-integer maxParallel", () => {
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, maxParallel: 0 }),
    ).toThrow('"maxParallel" must be a positive integer');
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, maxParallel: 2.5 }),
    ).toThrow('"maxParallel" must be a positive integer');
  });

  test("rejects a non-boolean failFast", () => {
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, failFast: "yes" }),
    ).toThrow('"failFast" must be a boolean');
  });

  test("rejects a negative or fractional maxSize", () => {
    expect(() =>
      parseConfig({ matrix: { os: ["ubuntu-latest"] }, maxSize: -1 }),
    ).toThrow('"maxSize" must be a non-negative integer');
  });
});
