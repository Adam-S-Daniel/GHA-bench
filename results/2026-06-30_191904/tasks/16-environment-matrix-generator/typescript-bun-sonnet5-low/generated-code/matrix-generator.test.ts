import { describe, test, expect } from "bun:test";
import { generateMatrix, type MatrixConfig } from "./matrix-generator";

// RED: first failing test - basic cartesian product of two dimensions
describe("generateMatrix - basic cartesian product", () => {
  test("produces cartesian product of os and node versions", () => {
    const config: MatrixConfig = {
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(4);
    expect(result.matrix.include).toContainEqual({ os: "ubuntu-latest", node: "18" });
    expect(result.matrix.include).toContainEqual({ os: "ubuntu-latest", node: "20" });
    expect(result.matrix.include).toContainEqual({ os: "windows-latest", node: "18" });
    expect(result.matrix.include).toContainEqual({ os: "windows-latest", node: "20" });
  });
});

describe("generateMatrix - exclude rules", () => {
  test("removes combinations matching all exclude keys", () => {
    const config: MatrixConfig = {
      dimensions: { os: ["ubuntu-latest", "windows-latest"], node: ["18", "20"] },
      exclude: [{ os: "windows-latest", node: "18" }],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(3);
    expect(result.matrix.include).not.toContainEqual({ os: "windows-latest", node: "18" });
  });

  test("partial-key exclude removes all rows matching that subset", () => {
    const config: MatrixConfig = {
      dimensions: { os: ["ubuntu-latest", "windows-latest"], node: ["18", "20"] },
      exclude: [{ os: "windows-latest" }],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include.every((r) => r.os === "ubuntu-latest")).toBe(true);
  });
});

describe("generateMatrix - include rules", () => {
  test("merges extra keys into matching existing rows", () => {
    const config: MatrixConfig = {
      dimensions: { os: ["ubuntu-latest"], node: ["18", "20"] },
      include: [{ node: "20", experimental: true }],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toContainEqual({ os: "ubuntu-latest", node: "20", experimental: true });
    expect(result.matrix.include).toContainEqual({ os: "ubuntu-latest", node: "18" });
  });

  test("appends new row when include entry matches nothing existing", () => {
    const config: MatrixConfig = {
      dimensions: { os: ["ubuntu-latest"], node: ["18"] },
      include: [{ os: "macos-latest", node: "21" }],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toContainEqual({ os: "macos-latest", node: "21" });
  });
});

describe("generateMatrix - fail-fast and max-parallel", () => {
  test("defaults fail-fast to true and omits max-parallel when unset", () => {
    const result = generateMatrix({ dimensions: { os: ["ubuntu-latest"] } });
    expect(result["fail-fast"]).toBe(true);
    expect(result["max-parallel"]).toBeUndefined();
  });

  test("respects explicit fail-fast and max-parallel", () => {
    const result = generateMatrix({
      dimensions: { os: ["ubuntu-latest"] },
      failFast: false,
      maxParallel: 2,
    });
    expect(result["fail-fast"]).toBe(false);
    expect(result["max-parallel"]).toBe(2);
  });

  test("throws on non-positive max-parallel", () => {
    expect(() =>
      generateMatrix({ dimensions: { os: ["ubuntu-latest"] }, maxParallel: 0 })
    ).toThrow(/max-parallel/);
  });
});

describe("generateMatrix - size validation", () => {
  test("throws when matrix exceeds maxSize", () => {
    expect(() =>
      generateMatrix({
        dimensions: { a: ["1", "2", "3"], b: ["1", "2", "3"] },
        maxSize: 5,
      })
    ).toThrow(/exceeds the maximum allowed size/);
  });

  test("throws when matrix is empty after exclusion", () => {
    expect(() =>
      generateMatrix({
        dimensions: { os: ["ubuntu-latest"] },
        exclude: [{ os: "ubuntu-latest" }],
      })
    ).toThrow(/zero combinations/);
  });

  test("throws when dimensions is empty", () => {
    expect(() => generateMatrix({ dimensions: {} })).toThrow(/at least one dimension/);
  });

  test("throws when a dimension has no values", () => {
    expect(() => generateMatrix({ dimensions: { os: [] } })).toThrow(/non-empty array/);
  });
});
