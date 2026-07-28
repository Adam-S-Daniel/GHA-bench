import { describe, it, expect } from "bun:test";
import { generateMatrix, MatrixConfig, MatrixOutput } from "./generator";

describe("Matrix Generator - Basic Functionality", () => {
  it("should generate a basic matrix from simple config", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "macos-latest"],
      nodeVersion: ["18", "20"],
    };

    const result = generateMatrix(config);

    expect(result).toBeDefined();
    expect(result.matrix).toBeDefined();
    expect(Array.isArray(result.matrix.include)).toBe(true);
    expect(result.matrix.include?.length).toBe(4);
  });

  it("should cartesian product os and versions", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["16", "18"],
    };

    const result = generateMatrix(config);
    const combinations = result.matrix.include || [];

    expect(combinations.length).toBe(4);
    expect(combinations).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "16",
    });
    expect(combinations).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "18",
    });
    expect(combinations).toContainEqual({
      os: "windows-latest",
      nodeVersion: "16",
    });
    expect(combinations).toContainEqual({
      os: "windows-latest",
      nodeVersion: "18",
    });
  });

  it("should support single values for dimensions", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const result = generateMatrix(config);

    expect(result.matrix.include?.length).toBe(1);
  });
});

describe("Matrix Generator - Feature Flags", () => {
  it("should include feature flags in matrix", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
      features: {
        experimental: [true, false],
      },
    };

    const result = generateMatrix(config);

    expect(result.matrix.include?.length).toBe(2);
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "18",
      experimental: true,
    });
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "18",
      experimental: false,
    });
  });
});

describe("Matrix Generator - Include/Exclude Rules", () => {
  it("should exclude specific combinations", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["16", "18"],
      exclude: [
        { os: "windows-latest", nodeVersion: "16" },
      ],
    };

    const result = generateMatrix(config);

    expect(result.matrix.include?.length).toBe(3);
    expect(result.matrix.exclude).toEqual([
      { os: "windows-latest", nodeVersion: "16" },
    ]);
  });

  it("should include only specified combinations", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["16", "18"],
      include: [
        { os: "ubuntu-latest", nodeVersion: "20", special: true },
      ],
    };

    const result = generateMatrix(config);

    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      nodeVersion: "20",
      special: true,
    });
  });
});

describe("Matrix Generator - Configuration Options", () => {
  it("should set fail-fast configuration", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
      failFast: false,
    };

    const result = generateMatrix(config);

    expect(result.strategy?.["fail-fast"]).toBe(false);
  });

  it("should set max-parallel limit", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["16", "18"],
      maxParallel: 2,
    };

    const result = generateMatrix(config);

    expect(result.strategy?.["max-parallel"]).toBe(2);
  });
});

describe("Matrix Generator - Validation", () => {
  it("should validate matrix size limit", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 50 }, (_, i) => `os-${i}`),
      nodeVersion: Array.from({ length: 50 }, (_, i) => `v${i}`),
      maxSize: 100,
    };

    expect(() => generateMatrix(config)).toThrow(/exceeds maximum/i);
  });

  it("should allow configured max-size", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 15 }, (_, i) => `os-${i}`),
      nodeVersion: Array.from({ length: 15 }, (_, i) => `v${i}`),
      maxSize: 225,
    };

    const result = generateMatrix(config);
    expect(result).toBeDefined();
  });

  it("should throw error for empty dimensions", () => {
    const config: MatrixConfig = {
      os: [],
      nodeVersion: ["18"],
    };

    expect(() => generateMatrix(config)).toThrow(/empty/i);
  });
});

describe("Matrix Generator - Output Format", () => {
  it("should output valid GitHub Actions matrix format", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
      failFast: true,
    };

    const result = generateMatrix(config);

    expect(result).toHaveProperty("matrix");
    expect(result).toHaveProperty("strategy");
    expect(result.matrix).toHaveProperty("include");
  });

  it("should serialize to valid JSON", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const result = generateMatrix(config);
    const json = JSON.stringify(result);

    expect(typeof json).toBe("string");
    const parsed = JSON.parse(json);
    expect(parsed.matrix).toBeDefined();
  });
});
