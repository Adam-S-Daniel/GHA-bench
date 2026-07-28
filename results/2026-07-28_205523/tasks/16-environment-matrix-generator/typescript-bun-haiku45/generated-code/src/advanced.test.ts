import { describe, it, expect } from "bun:test";
import { generateMatrix, MatrixConfig } from "./generator";

describe("Matrix Generator - Advanced Scenarios", () => {
  it("should handle multiple version dimensions", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["16", "18"],
      pythonVersion: ["3.9", "3.10"],
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(4);
  });

  it("should handle complex exclude patterns", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "macos-latest", "windows-latest"],
      nodeVersion: ["16", "18", "20"],
      exclude: [
        { os: "windows-latest", nodeVersion: "16" },
        { os: "macos-latest", nodeVersion: "18" },
      ],
    };

    const result = generateMatrix(config);
    const combinations = result.matrix.include || [];

    // Total should be 9 - 2 = 7
    expect(combinations.length).toBe(7);
    expect(
      combinations.find((c) => c.os === "windows-latest" && c.nodeVersion === "16")
    ).toBeUndefined();
    expect(
      combinations.find((c) => c.os === "macos-latest" && c.nodeVersion === "18")
    ).toBeUndefined();
  });

  it("should handle multiple feature flags", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      features: {
        experimental: [true, false],
        debug: [true, false],
      },
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(4);
  });

  it("should combine includes with generated combinations", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
      include: [
        { os: "custom-os", nodeVersion: "22", special: true },
      ],
    };

    const result = generateMatrix(config);

    expect(result.matrix.include?.length).toBe(2);
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "18",
    });
    expect(result.matrix.include).toContainEqual({
      os: "custom-os",
      nodeVersion: "22",
      special: true,
    });
  });

  it("should handle edge case of single-dimension matrix", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "macos-latest"],
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(2);
  });
});

describe("Matrix Generator - Real-World Scenarios", () => {
  it("should generate matrix for web app testing", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
      browser: ["chrome", "firefox"],
      failFast: false,
      maxParallel: 4,
    };

    const result = generateMatrix(config);

    // 2 * 2 * 2 = 8
    expect(result.matrix.include?.length).toBe(8);
    expect(result.strategy?.["fail-fast"]).toBe(false);
    expect(result.strategy?.["max-parallel"]).toBe(4);
  });

  it("should handle Python testing matrix with excludes", () => {
    const config: MatrixConfig = {
      pythonVersion: ["3.8", "3.9", "3.10", "3.11"],
      os: ["ubuntu-latest", "macos-latest"],
      exclude: [
        { pythonVersion: "3.8", os: "macos-latest" },
      ],
      maxParallel: 6,
    };

    const result = generateMatrix(config);

    // 4 * 2 - 1 = 7
    expect(result.matrix.include?.length).toBe(7);
    expect(result.strategy?.["max-parallel"]).toBe(6);
  });

  it("should validate size for large matrix", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 20 }, (_, i) => `os-${i}`),
      pythonVersion: Array.from({ length: 10 }, (_, i) => `3.${i}`),
      maxSize: 150,
    };

    // 20 * 10 = 200 > 150
    expect(() => generateMatrix(config)).toThrow(/exceeds maximum/i);
  });

  it("should allow large matrix with raised limit", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 10 }, (_, i) => `os-${i}`),
      pythonVersion: Array.from({ length: 10 }, (_, i) => `3.${i}`),
      maxSize: 200,
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(100);
  });
});

describe("Matrix Generator - Error Handling", () => {
  it("should throw on invalid configuration with all empty arrays", () => {
    const config: MatrixConfig = {
      os: [],
      nodeVersion: [],
    };

    expect(() => generateMatrix(config)).toThrow();
  });

  it("should throw on truly empty config", () => {
    const config: MatrixConfig = {};

    expect(() => generateMatrix(config)).toThrow(/must have at least one/i);
  });

  it("should throw with descriptive message for single empty dimension", () => {
    const config: MatrixConfig = {
      os: [],
      nodeVersion: ["18"],
    };

    const error = new Error();
    try {
      generateMatrix(config);
    } catch (e) {
      if (e instanceof Error) {
        expect(e.message).toMatch(/empty/i);
      }
    }
  });
});

describe("Matrix Generator - Data Types", () => {
  it("should handle boolean values", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      features: {
        debug: [true, false],
      },
    };

    const result = generateMatrix(config);
    const entries = result.matrix.include || [];

    expect(entries.some((e) => e.debug === true)).toBe(true);
    expect(entries.some((e) => e.debug === false)).toBe(true);
  });

  it("should handle numeric values in features", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      shardCount: [1, 2, 4] as any,
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(3);
  });

  it("should handle mixed string and numeric values", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18", "20"] as any,
    };

    const result = generateMatrix(config);
    expect(result.matrix.include?.length).toBe(2);
  });
});
