import { describe, it, expect } from "bun:test";
import { generateMatrix, MatrixConfig, MatrixOptions } from "./matrix";

describe("Environment Matrix Generator", () => {
  it("should generate a basic matrix from config", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const result = generateMatrix(config);

    expect(result.include).toBeDefined();
    expect(result.include.length).toBe(4); // 2 OS * 2 versions
  });

  it("should create all combinations in the matrix", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18", "20"],
    };

    const result = generateMatrix(config);
    const combinations = result.include.map((item: any) =>
      `${item.os}-${item.nodeVersion}`
    );

    expect(combinations).toContain("ubuntu-latest-18");
    expect(combinations).toContain("ubuntu-latest-20");
  });

  it("should apply exclude rules", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      exclude: [{ os: "windows-latest", nodeVersion: "18" }],
    };

    const result = generateMatrix(config, options);

    expect(result.exclude).toBeDefined();
    expect(result.exclude?.length).toBe(1);
  });

  it("should apply include rules and override defaults", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const options: MatrixOptions = {
      include: [{ os: "macos-latest", nodeVersion: "20" }],
    };

    const result = generateMatrix(config, options);

    // Should have original combinations plus includes
    expect(result.include.length).toBeGreaterThan(0);
    const hasMacOS = result.include.some((item: any) => item.os === "macos-latest");
    expect(hasMacOS).toBe(true);
  });

  it("should set max-parallel limit", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      maxParallel: 2,
    };

    const result = generateMatrix(config, options);

    expect(result["max-parallel"]).toBe(2);
  });

  it("should set fail-fast configuration", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const options: MatrixOptions = {
      failFast: false,
    };

    const result = generateMatrix(config, options);

    expect(result["fail-fast"]).toBe(false);
  });

  it("should validate matrix size does not exceed maximum", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20", "22"],
      pythonVersion: ["3.8", "3.9", "3.10"],
    };

    const options: MatrixOptions = {
      maxSize: 10,
    };

    expect(() => generateMatrix(config, options)).toThrow();
  });

  it("should allow matrix within size limit", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      maxSize: 10,
    };

    const result = generateMatrix(config, options);
    expect(result.include.length).toBeLessThanOrEqual(10);
  });

  it("should handle empty config gracefully", () => {
    const config: MatrixConfig = {};

    const result = generateMatrix(config);

    expect(result.include).toEqual([]);
  });

  it("should handle single value arrays", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const result = generateMatrix(config);

    expect(result.include.length).toBe(1);
    expect(result.include[0]).toEqual({
      os: "ubuntu-latest",
      nodeVersion: "18",
    });
  });

  it("should handle three-dimensional matrix", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
      pythonVersion: ["3.8", "3.9"],
    };

    const result = generateMatrix(config);

    // 2 * 2 * 2 = 8 combinations
    expect(result.include.length).toBe(8);
  });

  it("should correctly exclude combinations", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      exclude: [
        { os: "windows-latest", nodeVersion: "18" },
        { os: "ubuntu-latest", nodeVersion: "20" },
      ],
    };

    const result = generateMatrix(config, options);

    expect(result.exclude?.length).toBe(2);
  });

  it("should merge include rules with generated matrix", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest"],
      nodeVersion: ["18"],
    };

    const options: MatrixOptions = {
      include: [
        { os: "macos-latest", nodeVersion: "20" },
        { os: "macos-latest", nodeVersion: "22" },
      ],
    };

    const result = generateMatrix(config, options);

    // Should have 1 base + 2 includes = 3
    expect(result.include.length).toBe(3);

    const hasMacOS20 = result.include.some(
      (item: any) => item.os === "macos-latest" && item.nodeVersion === "20"
    );
    expect(hasMacOS20).toBe(true);
  });

  it("should handle custom config keys", () => {
    const config: MatrixConfig = {
      platform: ["x86", "arm64"],
      compiler: ["gcc", "clang"],
    };

    const result = generateMatrix(config);

    expect(result.include.length).toBe(4);

    const hasGccX86 = result.include.some(
      (item: any) => item.platform === "x86" && item.compiler === "gcc"
    );
    expect(hasGccX86).toBe(true);
  });

  it("should validate matrix size exactly at limit", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      maxSize: 4, // Exactly 2*2=4
    };

    const result = generateMatrix(config, options);
    expect(result.include.length).toBe(4);
  });

  it("should reject matrix when size exceeds limit by 1", () => {
    const config: MatrixConfig = {
      os: ["ubuntu-latest", "windows-latest"],
      nodeVersion: ["18", "20"],
    };

    const options: MatrixOptions = {
      maxSize: 3, // Less than 2*2=4
    };

    expect(() => generateMatrix(config, options)).toThrow();
  });
});
