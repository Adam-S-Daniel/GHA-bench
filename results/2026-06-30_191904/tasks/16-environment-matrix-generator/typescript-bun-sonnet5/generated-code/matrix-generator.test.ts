// Unit tests for the pure matrix-generation logic.
//
// TDD note: these tests were written before matrix-generator.ts existed, so
// the very first `bun test` run fails at import time. Each describe block
// below was grown incrementally: red (test written against a not-yet-existing
// export), green (minimal implementation added), refactor.
import { describe, expect, test } from "bun:test";
import {
  applyExclude,
  applyInclude,
  cartesianProduct,
  DEFAULT_MAX_MATRIX_SIZE,
  generateMatrix,
  MatrixConfigError,
  MatrixSizeExceededError,
} from "./matrix-generator";

describe("cartesianProduct", () => {
  test("expands a single axis into one combination per value", () => {
    expect(cartesianProduct({ os: ["ubuntu-latest", "windows-latest"] })).toEqual([
      { os: "ubuntu-latest" },
      { os: "windows-latest" },
    ]);
  });

  test("expands two axes in row-major order (first axis varies slowest)", () => {
    expect(
      cartesianProduct({ os: ["ubuntu-latest", "windows-latest"], version: ["18", "20"] }),
    ).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
      { os: "windows-latest", version: "18" },
      { os: "windows-latest", version: "20" },
    ]);
  });

  test("expands three axes", () => {
    const result = cartesianProduct({
      os: ["ubuntu-latest"],
      version: ["18", "20"],
      coverage: [true, false],
    });
    expect(result).toHaveLength(4);
    expect(result).toContainEqual({ os: "ubuntu-latest", version: "18", coverage: true });
    expect(result).toContainEqual({ os: "ubuntu-latest", version: "20", coverage: false });
  });

  test("an empty axis collapses the whole product to zero combinations", () => {
    expect(cartesianProduct({ os: [], version: ["18"] })).toEqual([]);
  });

  test("no axes at all yields a single empty combination", () => {
    expect(cartesianProduct({})).toEqual([{}]);
  });

  test("supports non-string axis values (numbers and booleans)", () => {
    expect(cartesianProduct({ retries: [1, 2], strict: [true] })).toEqual([
      { retries: 1, strict: true },
      { retries: 2, strict: true },
    ]);
  });
});

describe("applyExclude", () => {
  const base = cartesianProduct({
    os: ["ubuntu-latest", "windows-latest"],
    version: ["18", "20"],
  });

  test("removes only the combination matching every key/value pair", () => {
    const result = applyExclude(base, [{ os: "windows-latest", version: "18" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
      { os: "windows-latest", version: "20" },
    ]);
  });

  test("a partial (single-key) exclude rule removes every matching combination", () => {
    const result = applyExclude(base, [{ os: "windows-latest" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
    ]);
  });

  test("an exclude rule referencing an unknown key matches nothing", () => {
    const result = applyExclude(base, [{ arch: "arm64" }]);
    expect(result).toEqual(base);
  });

  test("an empty exclude list leaves the matrix unchanged", () => {
    expect(applyExclude(base, [])).toEqual(base);
  });
});

describe("applyInclude", () => {
  test("extends only the combinations matching the include's overlapping key", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest", "windows-latest"], version: ["18", "20"] });
    const result = applyInclude(base, [{ os: "ubuntu-latest", coverage: true }], new Set(["os", "version"]));
    expect(result).toEqual([
      { os: "ubuntu-latest", version: "18", coverage: true },
      { os: "ubuntu-latest", version: "20", coverage: true },
      { os: "windows-latest", version: "18" },
      { os: "windows-latest", version: "20" },
    ]);
  });

  test("an include with no key overlapping an original axis extends every combination", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest"], version: ["18", "20"] });
    const result = applyInclude(base, [{ tier: "beta" }], new Set(["os", "version"]));
    expect(result).toEqual([
      { os: "ubuntu-latest", version: "18", tier: "beta" },
      { os: "ubuntu-latest", version: "20", tier: "beta" },
    ]);
  });

  test("an include that matches no original combination becomes a new standalone row", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest", "windows-latest"], version: ["18", "20"] });
    const result = applyInclude(base, [{ os: "macos-latest", version: "20", experimental: true }], new Set(["os", "version"]));
    expect(result).toEqual([
      ...base,
      { os: "macos-latest", version: "20", experimental: true },
    ]);
  });

  test("a later include can overwrite a field an earlier include added, but never an original axis value", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest"], version: ["18"] });
    const result = applyInclude(
      base,
      [
        { tier: "beta" },
        { os: "ubuntu-latest", tier: "stable" },
      ],
      new Set(["os", "version"]),
    );
    expect(result).toEqual([{ os: "ubuntu-latest", version: "18", tier: "stable" }]);
  });

  test("standalone rows created by one include are never merge targets for a later include", () => {
    // GitHub's own canonical example (see the `include` docs for
    // `jobs.<job_id>.strategy.matrix`): a two-axis matrix plus four include
    // rules produces six final rows, not five — the two `fruit: banana`
    // rules each stand alone rather than merging into each other.
    const base = cartesianProduct({ fruit: ["apple", "pear"], animal: ["cat", "dog"] });
    const result = applyInclude(
      base,
      [
        { color: "green" },
        { color: "pink", animal: "cat" },
        { fruit: "banana" },
        { fruit: "banana", animal: "cat" },
      ],
      new Set(["fruit", "animal"]),
    );
    expect(result).toEqual([
      { fruit: "apple", animal: "cat", color: "pink" },
      { fruit: "apple", animal: "dog", color: "green" },
      { fruit: "pear", animal: "cat", color: "pink" },
      { fruit: "pear", animal: "dog", color: "green" },
      { fruit: "banana" },
      { fruit: "banana", animal: "cat" },
    ]);
  });

  test("an empty include list leaves the matrix unchanged", () => {
    const base = cartesianProduct({ os: ["ubuntu-latest"] });
    expect(applyInclude(base, [], new Set(["os"]))).toEqual(base);
  });
});

describe("generateMatrix", () => {
  test("builds the os x version cross product with default fail-fast and no max-parallel", () => {
    const result = generateMatrix({ os: ["ubuntu-latest", "windows-latest"], version: ["18", "20"] });
    expect(result["fail-fast"]).toBe(true);
    expect(result["max-parallel"]).toBeUndefined();
    expect(result.matrixSize).toBe(4);
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
      { os: "windows-latest", version: "18" },
      { os: "windows-latest", version: "20" },
    ]);
  });

  test("merges feature-flag axes alongside os and version", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      version: ["18"],
      flags: { coverage: [true, false] },
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", version: "18", coverage: true },
      { os: "ubuntu-latest", version: "18", coverage: false },
    ]);
  });

  test("passes through custom failFast and maxParallel", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      version: ["18"],
      failFast: false,
      maxParallel: 2,
    });
    expect(result["fail-fast"]).toBe(false);
    expect(result["max-parallel"]).toBe(2);
  });

  test("applies exclude before include, matching GitHub's documented order", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "windows-latest"],
      version: ["18", "20"],
      exclude: [{ os: "windows-latest", version: "18" }],
      include: [{ os: "macos-latest", version: "20", experimental: true }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", version: "18" },
      { os: "ubuntu-latest", version: "20" },
      { os: "windows-latest", version: "20" },
      { os: "macos-latest", version: "20", experimental: true },
    ]);
    expect(result.matrixSize).toBe(4);
  });

  test("throws MatrixConfigError when os is missing or empty", () => {
    expect(() => generateMatrix({ os: [], version: ["18"] } as any)).toThrow(MatrixConfigError);
    expect(() => generateMatrix({ version: ["18"] } as any)).toThrow(MatrixConfigError);
  });

  test("throws MatrixConfigError when version is missing or empty", () => {
    expect(() => generateMatrix({ os: ["ubuntu-latest"], version: [] } as any)).toThrow(MatrixConfigError);
  });

  test("throws MatrixConfigError when a flags axis collides with a reserved axis name", () => {
    expect(() =>
      generateMatrix({ os: ["ubuntu-latest"], version: ["18"], flags: { os: ["extra"] } } as any),
    ).toThrow(MatrixConfigError);
  });

  test("defaults maxMatrixSize to 256, GitHub's own hard cap", () => {
    expect(DEFAULT_MAX_MATRIX_SIZE).toBe(256);
  });

  test("throws MatrixSizeExceededError with the actual and max size when the matrix is too big", () => {
    let error: unknown;
    try {
      generateMatrix({
        os: ["ubuntu-latest", "windows-latest", "macos-latest"],
        version: ["18", "20", "22"],
        maxMatrixSize: 4,
      });
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(MatrixSizeExceededError);
    const sizeError = error as MatrixSizeExceededError;
    expect(sizeError.size).toBe(9);
    expect(sizeError.maxMatrixSize).toBe(4);
    expect(sizeError.message).toContain("9");
    expect(sizeError.message).toContain("4");
  });

  test("does not throw when the matrix is exactly at maxMatrixSize", () => {
    expect(() =>
      generateMatrix({ os: ["ubuntu-latest", "windows-latest"], version: ["18"], maxMatrixSize: 2 }),
    ).not.toThrow();
  });
});
