// Red/Green TDD: this is the FIRST failing test written before any implementation exists.
import { describe, expect, test } from "bun:test";
import { generateMatrix } from "../src/matrix-generator";

describe("generateMatrix - basic cartesian product", () => {
  test("produces the cartesian product of all dimensions", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
    });

    expect(result.matrix.include).toHaveLength(4);
    expect(result.matrix.include).toEqual(
      expect.arrayContaining([
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "18" },
        { os: "windows-latest", node: "20" },
      ]),
    );
  });
});

describe("generateMatrix - include rules", () => {
  test("merges extra keys into every existing row that matches the include's shared keys", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18"],
      },
      include: [{ os: "ubuntu-latest", extra_flag: "true" }],
    });

    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toEqual(
      expect.arrayContaining([
        { os: "ubuntu-latest", node: "18", extra_flag: "true" },
        { os: "windows-latest", node: "18" },
      ]),
    );
  });

  test("appends extra combinations listed under include that aren't covered by dimensions", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest"],
        node: ["18"],
      },
      include: [{ os: "macos-latest", node: "21", experimental: "true" }],
    });

    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toEqual(
      expect.arrayContaining([
        { os: "ubuntu-latest", node: "18" },
        { os: "macos-latest", node: "21", experimental: "true" },
      ]),
    );
  });
});

describe("generateMatrix - exclude rules", () => {
  test("removes combinations matching every key/value pair in an exclude entry", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
      exclude: [{ os: "windows-latest", node: "18" }],
    });

    expect(result.matrix.include).toHaveLength(3);
    expect(result.matrix.include).toEqual(
      expect.arrayContaining([
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
        { os: "windows-latest", node: "20" },
      ]),
    );
  });

  test("a partial exclude (subset of keys) removes all matching rows", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
      exclude: [{ os: "windows-latest" }],
    });

    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toEqual(
      expect.arrayContaining([
        { os: "ubuntu-latest", node: "18" },
        { os: "ubuntu-latest", node: "20" },
      ]),
    );
  });
});

describe("generateMatrix - fail-fast and max-parallel", () => {
  test("defaults fail-fast to true and omits max-parallel when not set", () => {
    const result = generateMatrix({
      dimensions: { os: ["ubuntu-latest"] },
    });

    expect(result.matrix["fail-fast"]).toBe(true);
    expect(result.matrix["max-parallel"]).toBeUndefined();
  });

  test("honors an explicit fail-fast=false and a max-parallel value", () => {
    const result = generateMatrix({
      dimensions: { os: ["ubuntu-latest"] },
      failFast: false,
      maxParallel: 2,
    });

    expect(result.matrix["fail-fast"]).toBe(false);
    expect(result.matrix["max-parallel"]).toBe(2);
  });

  test("rejects a max-parallel value less than 1", () => {
    expect(() =>
      generateMatrix({
        dimensions: { os: ["ubuntu-latest"] },
        maxParallel: 0,
      }),
    ).toThrow(/max-parallel/i);
  });
});

describe("generateMatrix - matrix size validation", () => {
  test("throws a descriptive error when the generated matrix exceeds maxMatrixSize", () => {
    expect(() =>
      generateMatrix({
        dimensions: {
          os: ["ubuntu-latest", "windows-latest", "macos-latest"],
          node: ["16", "18", "20"],
        },
        maxMatrixSize: 5,
      }),
    ).toThrow(/exceeds maximum matrix size/i);
  });

  test("GitHub Actions' own hard limit of 256 is enforced even without maxMatrixSize", () => {
    const dimensions: Record<string, string[]> = {
      a: Array.from({ length: 17 }, (_, i) => `v${i}`),
      b: Array.from({ length: 17 }, (_, i) => `v${i}`),
    };

    expect(() => generateMatrix({ dimensions })).toThrow(/256/);
  });

  test("allows a matrix within the configured maxMatrixSize", () => {
    const result = generateMatrix({
      dimensions: {
        os: ["ubuntu-latest", "windows-latest"],
        node: ["18", "20"],
      },
      maxMatrixSize: 10,
    });

    expect(result.matrix.include).toHaveLength(4);
  });
});
