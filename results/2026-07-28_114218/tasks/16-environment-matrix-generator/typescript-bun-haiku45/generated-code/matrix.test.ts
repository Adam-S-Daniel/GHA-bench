import { describe, it, expect } from "bun:test";
import { generateMatrix, MatrixConfig, BuildMatrix, loadConfigAndGenerate } from "./matrix";

describe("Matrix Generator - Basic", () => {
  it("should create an empty matrix from empty config", () => {
    const config: MatrixConfig = {
      os: [],
      languages: [],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toEqual([]);
  });

  it("should generate a single-axis cartesian product", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: [],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(1);
    expect(result.matrix.include[0]).toEqual({
      os: "ubuntu-latest",
    });
  });

  it("should generate cartesian product for two axes", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python"],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      language: "python",
    });
    expect(result.matrix.include).toContainEqual({
      os: "windows-latest",
      language: "python",
    });
  });

  it("should handle multiple values on all axes", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "macos-latest"],
      languages: ["python", "node"],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(4);
  });
});

describe("Matrix Generator - Advanced Features", () => {
  it("should support feature flags", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: ["python"],
      features: ["debug", "release"],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      language: "python",
      feature: "debug",
    });
  });

  it("should support node versions", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: ["javascript"],
      nodeVersions: ["16", "18", "20"],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(3);
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      language: "javascript",
      nodeVersion: "18",
    });
  });

  it("should support include rules", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: ["python"],
      include: [
        {
          os: "windows-latest",
          language: "python",
          special: "custom",
        },
      ],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toContainEqual({
      os: "windows-latest",
      language: "python",
      special: "custom",
    });
  });

  it("should support exclude rules", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python", "node"],
      exclude: [
        {
          os: "windows-latest",
          language: "node",
        },
      ],
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(3);
    expect(result.matrix.include).not.toContainEqual({
      os: "windows-latest",
      language: "node",
    });
  });

  it("should apply max-parallel limit", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python"],
      maxParallel: 1,
    };
    const result = generateMatrix(config);
    expect(result.maxParallel).toBe(1);
  });

  it("should apply fail-fast setting", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: ["python"],
      failFast: false,
    };
    const result = generateMatrix(config);
    expect(result.failFast).toBe(false);
  });

  it("should include excludes in matrix output", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python"],
      exclude: [
        {
          os: "windows-latest",
          language: "python",
        },
      ],
    };
    const result = generateMatrix(config);
    expect(result.matrix.exclude).toBeDefined();
    expect(result.matrix.exclude).toHaveLength(1);
  });
});

describe("Matrix Generator - Validation", () => {
  it("should reject matrix exceeding max size", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 50 }, (_, i) => `os-${i}`),
      languages: Array.from({ length: 50 }, (_, i) => `lang-${i}`),
      maxSize: 100,
    };
    expect(() => generateMatrix(config)).toThrow("Matrix size");
  });

  it("should validate matrix size correctly", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python"],
      maxSize: 2,
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(2);
  });

  it("should validate required fields", () => {
    const config: any = {
      os: ["ubuntu-latest"],
    };
    expect(() => generateMatrix(config)).toThrow();
  });

  it("should use default maxSize of 1000", () => {
    const config: MatrixConfig = {
      os: Array.from({ length: 30 }, (_, i) => `os-${i}`),
      languages: Array.from({ length: 30 }, (_, i) => `lang-${i}`),
    };
    const result = generateMatrix(config);
    expect(result.matrix.include).toHaveLength(900);
  });
});

describe("Matrix Generator - Complex Scenarios", () => {
  it("should handle multiple axes with all features", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "macos-latest"],
      languages: ["python", "node"],
      features: ["debug", "release"],
      nodeVersions: ["18", "20"],
    };
    const result = generateMatrix(config);
    // 2 os × 2 languages × 2 features × 2 node versions = 16
    expect(result.matrix.include).toHaveLength(16);
  });

  it("should handle multiple excludes", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest", "macos-latest"],
      languages: ["python", "node", "ruby"],
      exclude: [
        { os: "windows-latest", language: "ruby" },
        { os: "macos-latest", language: "node" },
        { os: "ubuntu-latest", language: "python" },
      ],
    };
    const result = generateMatrix(config);
    // 3 × 3 = 9, minus 3 excludes = 6
    expect(result.matrix.include).toHaveLength(6);
  });

  it("should handle exclude with partial matches", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      languages: ["python", "node"],
      exclude: [
        { os: "windows-latest" }, // Exclude all windows combinations
      ],
    };
    const result = generateMatrix(config);
    // Only ubuntu combinations should remain: 1 os × 2 languages = 2
    expect(result.matrix.include).toHaveLength(2);
  });

  it("should combine includes and excludes correctly", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      languages: ["python"],
      exclude: [
        { os: "ubuntu-latest", language: "python" },
      ],
      include: [
        { os: "custom-runner", language: "go" },
        { os: "ubuntu-latest", language: "python", experimental: true },
      ],
    };
    const result = generateMatrix(config);
    // Empty from cartesian, then add 2 includes = 2
    expect(result.matrix.include).toHaveLength(2);
    expect(result.matrix.include).toContainEqual({
      os: "custom-runner",
      language: "go",
    });
    expect(result.matrix.include).toContainEqual({
      os: "ubuntu-latest",
      language: "python",
      experimental: true,
    });
  });
});

describe("Matrix Generator - File Loading", () => {
  it("should load config from JSON file", async () => {
    const result = await loadConfigAndGenerate("fixtures/simple-config.json");
    expect(result.matrix.include).toHaveLength(4);
  });

  it("should load advanced config from file", async () => {
    const result = await loadConfigAndGenerate("fixtures/advanced-config.json");
    expect(result.matrix.include.length).toBeGreaterThan(0);
    expect(result.maxParallel).toBe(5);
    expect(result.failFast).toBe(false);
  });
});
