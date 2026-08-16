import { expect, describe, it } from "bun:test";
import { generateMatrix } from "./matrix";

describe("Matrix Generator", () => {
  it("should generate a simple matrix from basic config", () => {
    const config = {
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
    };

    const result = generateMatrix(config);

    expect(result).toBeDefined();
    expect(result.include).toBeDefined();
    expect(Array.isArray(result.include)).toBe(true);
    expect(result.include.length).toBe(4); // 2 OS × 2 node versions
  });

  it("should create combinations in include array", () => {
    const config = {
      os: ["ubuntu-latest"],
      node: ["20"],
    };

    const result = generateMatrix(config);
    const firstCombination = result.include[0];

    expect(firstCombination.os).toBe("ubuntu-latest");
    expect(firstCombination.node).toBe("20");
  });

  it("should respect exclude rules", () => {
    const config = {
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
      exclude: [
        { os: "windows-latest", node: "18" }
      ],
    };

    const result = generateMatrix(config);

    expect(result.include.length).toBe(3); // 4 - 1 excluded
    const windowsEighteen = result.include.find(
      (c) => c.os === "windows-latest" && c.node === "18"
    );
    expect(windowsEighteen).toBeUndefined();
  });

  it("should support max-parallel limit", () => {
    const config = {
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
      maxParallel: 2,
    };

    const result = generateMatrix(config);

    expect(result["max-parallel"]).toBe(2);
  });

  it("should support fail-fast configuration", () => {
    const config = {
      os: ["ubuntu-latest"],
      node: ["20"],
      failFast: false,
    };

    const result = generateMatrix(config);

    expect(result["fail-fast"]).toBe(false);
  });

  it("should validate matrix size doesn't exceed maximum", () => {
    const config = {
      os: Array(20).fill(0).map((_, i) => `os-${i}`),
      node: Array(20).fill(0).map((_, i) => `node-${i}`),
      maxSize: 100,
    };

    expect(() => generateMatrix(config)).toThrow();
  });

  it("should allow configuration of max size", () => {
    const config = {
      os: Array(10).fill(0).map((_, i) => `os-${i}`),
      node: Array(10).fill(0).map((_, i) => `node-${i}`),
      maxSize: 200,
    };

    const result = generateMatrix(config);
    expect(result.include.length).toBeLessThanOrEqual(200);
  });

  it("should support include rules to add extra combinations", () => {
    const config = {
      os: ["ubuntu-latest"],
      node: ["20"],
      include: [
        { os: "macos-latest", node: "20", extra: "feature-flag" }
      ],
    };

    const result = generateMatrix(config);

    expect(result.include.length).toBe(2); // 1 base + 1 included
    const macos = result.include.find((c) => c.os === "macos-latest");
    expect(macos).toBeDefined();
    expect(macos?.extra).toBe("feature-flag");
  });

  it("should handle empty configuration gracefully", () => {
    const config = {};

    const result = generateMatrix(config);

    expect(result.include.length).toBe(0);
  });

  it("should exclude matching combinations with multiple properties", () => {
    const config = {
      os: ["ubuntu-latest", "windows-latest"],
      node: ["18", "20"],
      python: ["3.9", "3.10"],
      exclude: [
        { os: "windows-latest", node: "18", python: "3.9" },
        { os: "ubuntu-latest", python: "3.10" },
      ],
    };

    const result = generateMatrix(config);

    expect(result.include.length).toBe(5); // 8 - 1 - 2 excluded (2×2×2=8, minus windows-18-3.9, minus ubuntu-3.10 pair)
  });

  it("should produce valid JSON output", () => {
    const config = {
      os: ["ubuntu-latest"],
      node: ["20"],
      maxParallel: 5,
      failFast: true,
    };

    const result = generateMatrix(config);
    const json = JSON.stringify(result);

    expect(json).toBeDefined();
    expect(json.length).toBeGreaterThan(0);
    const parsed = JSON.parse(json);
    expect(parsed.include).toBeDefined();
    expect(parsed["max-parallel"]).toBe(5);
    expect(parsed["fail-fast"]).toBe(true);
  });
});
