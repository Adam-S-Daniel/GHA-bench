// TDD test suite for the environment matrix generator.
//
// We follow a red/green cycle: each `describe` block below was written as a
// failing test first, then the minimum implementation was added to
// `matrix-generator.ts` to make it pass.
import { describe, expect, test } from "bun:test";
import {
  applyExclude,
  applyInclude,
  cartesianProduct,
  generateMatrix,
  MatrixSizeError,
  type MatrixConfig,
} from "./matrix-generator";

describe("cartesianProduct", () => {
  // RED #1: the most basic building block — expand axes into combinations.
  test("expands a single axis", () => {
    expect(cartesianProduct({ os: ["linux", "windows"] })).toEqual([
      { os: "linux" },
      { os: "windows" },
    ]);
  });

  test("expands two axes in row-major order", () => {
    expect(
      cartesianProduct({ os: ["linux", "windows"], node: ["18", "20"] }),
    ).toEqual([
      { os: "linux", node: "18" },
      { os: "linux", node: "20" },
      { os: "windows", node: "18" },
      { os: "windows", node: "20" },
    ]);
  });

  test("returns a single empty combination when there are no axes", () => {
    expect(cartesianProduct({})).toEqual([{}]);
  });

  test("yields no combinations when any axis is empty", () => {
    expect(cartesianProduct({ os: ["linux"], node: [] })).toEqual([]);
  });

  test("supports non-string axis values (booleans, numbers)", () => {
    expect(
      cartesianProduct({ node: [18, 20], coverage: [true, false] }),
    ).toEqual([
      { node: 18, coverage: true },
      { node: 18, coverage: false },
      { node: 20, coverage: true },
      { node: 20, coverage: false },
    ]);
  });
});

describe("applyExclude", () => {
  const combos = cartesianProduct({
    os: ["linux", "windows"],
    node: ["18", "20"],
  });

  // RED #2: a partial exclude removes every combination matching all its pairs.
  test("removes combinations matching all key/value pairs of an exclude entry", () => {
    expect(applyExclude(combos, [{ os: "windows", node: "18" }])).toEqual([
      { os: "linux", node: "18" },
      { os: "linux", node: "20" },
      { os: "windows", node: "20" },
    ]);
  });

  test("a partial exclude matches multiple combinations", () => {
    expect(applyExclude(combos, [{ os: "windows" }])).toEqual([
      { os: "linux", node: "18" },
      { os: "linux", node: "20" },
    ]);
  });

  test("returns input unchanged when no exclude entries are given", () => {
    expect(applyExclude(combos, [])).toEqual(combos);
  });
});

describe("applyInclude", () => {
  // RED #3: faithfully reproduce GitHub's documented include algorithm.
  // https://docs.github.com/actions/using-jobs/using-a-matrix-for-your-jobs
  test("matches GitHub's canonical fruit/animal example", () => {
    const base = cartesianProduct({
      fruit: ["apple", "pear"],
      animal: ["cat", "dog"],
    });
    const include = [
      { color: "green" },
      { color: "pink", animal: "cat" },
      { fruit: "apple", shape: "circle" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ];
    expect(
      applyInclude(base, include, new Set(["fruit", "animal"])),
    ).toEqual([
      { fruit: "apple", animal: "cat", color: "pink", shape: "circle" },
      { fruit: "apple", animal: "dog", color: "green", shape: "circle" },
      { fruit: "pear", animal: "cat", color: "pink" },
      { fruit: "pear", animal: "dog", color: "green" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ]);
  });

  test("adds a fully matching include without creating new rows", () => {
    const base = cartesianProduct({ os: ["linux"], node: ["18", "20"] });
    expect(
      applyInclude(base, [{ os: "linux", node: "20", coverage: true }], new Set(["os", "node"])),
    ).toEqual([
      { os: "linux", node: "18" },
      { os: "linux", node: "20", coverage: true },
    ]);
  });
});

describe("generateMatrix", () => {
  // RED #4: end-to-end orchestration with strategy fields and size guard.
  test("produces expanded combinations with strategy metadata", () => {
    const config: MatrixConfig = {
      matrix: { os: ["linux", "windows"], node: ["18", "20"] },
      failFast: false,
      maxParallel: 2,
    };
    const result = generateMatrix(config);
    expect(result.failFast).toBe(false);
    expect(result.maxParallel).toBe(2);
    expect(result.size).toBe(4);
    expect(result.include).toHaveLength(4);
  });

  test("defaults failFast to true and maxParallel to null", () => {
    const result = generateMatrix({ matrix: { os: ["linux"] } });
    expect(result.failFast).toBe(true);
    expect(result.maxParallel).toBeNull();
  });

  test("applies exclude then include in the correct order", () => {
    const result = generateMatrix({
      matrix: { os: ["linux", "windows"], node: ["18", "20"] },
      exclude: [{ os: "windows", node: "18" }],
      include: [{ os: "macos", node: "20" }],
    });
    expect(result.include).toEqual([
      { os: "linux", node: "18" },
      { os: "linux", node: "20" },
      { os: "windows", node: "20" },
      { os: "macos", node: "20" },
    ]);
    expect(result.size).toBe(4);
  });

  test("throws MatrixSizeError when the matrix exceeds maxSize", () => {
    expect(() =>
      generateMatrix({
        matrix: { os: ["a", "b", "c"], node: ["1", "2"] },
        maxSize: 4,
      }),
    ).toThrow(MatrixSizeError);
  });

  test("rejects a config without a matrix object", () => {
    // @ts-expect-error intentionally invalid input
    expect(() => generateMatrix({})).toThrow(/matrix/i);
  });

  test("rejects a non-array axis value", () => {
    expect(() =>
      // @ts-expect-error intentionally invalid input
      generateMatrix({ matrix: { os: "linux" } }),
    ).toThrow(/array/i);
  });
});
