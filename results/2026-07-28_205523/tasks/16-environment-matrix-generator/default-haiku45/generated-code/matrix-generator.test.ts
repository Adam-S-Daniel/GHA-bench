// Red/Green TDD: Start with failing tests, then implement
import { describe, it, expect } from "bun:test";
import { generateMatrix, MatrixConfig, GitHubMatrix } from "./matrix-generator";

describe("Environment Matrix Generator", () => {
  describe("Basic matrix generation", () => {
    it("should generate a simple matrix from OS and version configs", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include).toBeDefined();
      expect(matrix.include.length).toBe(4);
      // Should have all combinations: ubuntu+18, ubuntu+20, windows+18, windows+20
      expect(matrix.include.some((m) => m.os === "ubuntu-latest" && m.nodeVersion === "18")).toBe(true);
      expect(matrix.include.some((m) => m.os === "windows-latest" && m.nodeVersion === "20")).toBe(true);
    });

    it("should handle single dimension configs", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(1);
      expect(matrix.include[0].os).toBe("ubuntu-latest");
    });

    it("should handle empty arrays by excluding from matrix", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        nodeVersion: [],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(1);
      expect(matrix.include[0].nodeVersion).toBeUndefined();
    });
  });

  describe("Include and exclude rules", () => {
    it("should apply include rules to add specific combinations", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        include: [
          { os: "macos-latest", nodeVersion: "20", experimental: true },
        ],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(2);
      expect(
        matrix.include.some(
          (m) => m.os === "macos-latest" && m.nodeVersion === "20" && m.experimental === true
        )
      ).toBe(true);
    });

    it("should apply exclude rules to remove specific combinations", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
        exclude: [{ os: "windows-latest", nodeVersion: "18" }],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(3);
      expect(
        matrix.include.some((m) => m.os === "windows-latest" && m.nodeVersion === "18")
      ).toBe(false);
    });

    it("should support exclude with partial matching", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
        exclude: [{ os: "windows-latest" }],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(2);
      expect(matrix.include.every((m) => m.os !== "windows-latest")).toBe(true);
    });
  });

  describe("Fail-fast configuration", () => {
    it("should set fail-fast to true when configured", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        failFast: true,
      };

      const matrix = generateMatrix(config);

      expect(matrix["fail-fast"]).toBe(true);
    });

    it("should set fail-fast to false when configured", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        failFast: false,
      };

      const matrix = generateMatrix(config);

      expect(matrix["fail-fast"]).toBe(false);
    });

    it("should not set fail-fast if not configured", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
      };

      const matrix = generateMatrix(config);

      expect(matrix["fail-fast"]).toBeUndefined();
    });
  });

  describe("Max parallel configuration", () => {
    it("should set max-parallel when configured", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        maxParallel: 2,
      };

      const matrix = generateMatrix(config);

      expect(matrix["max-parallel"]).toBe(2);
    });

    it("should not set max-parallel if not configured", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
      };

      const matrix = generateMatrix(config);

      expect(matrix["max-parallel"]).toBeUndefined();
    });
  });

  describe("Matrix size validation", () => {
    it("should allow matrix within max size limit", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
        maxSize: 10,
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBeLessThanOrEqual(4);
    });

    it("should throw error when matrix exceeds max size", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20", "21"],
        maxSize: 2,
      };

      expect(() => generateMatrix(config)).toThrow();
    });

    it("should validate max size after excludes are applied", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
        exclude: [
          { os: "ubuntu-latest", nodeVersion: "18" },
          { os: "ubuntu-latest", nodeVersion: "20" },
        ],
        maxSize: 2,
      };

      const result = generateMatrix(config);
      expect(result.include.length).toBe(2);
    });

    it("should consider includes when validating size", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        include: [
          { os: "macos-latest", nodeVersion: "20" },
          { os: "macos-latest", nodeVersion: "21" },
        ],
        maxSize: 2,
      };

      expect(() => generateMatrix(config)).toThrow();
    });
  });

  describe("Complex multi-dimension matrices", () => {
    it("should generate all combinations for 3+ dimensions", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest"],
        nodeVersion: ["18", "20"],
        pyVersion: ["3.9", "3.11"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(8); // 2 * 2 * 2
    });

    it("should handle many OS options", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-latest", "macos-latest", "macos-13"],
        nodeVersion: ["18", "20"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(8); // 4 * 2
      expect(matrix.include.every((m) => m.nodeVersion !== undefined)).toBe(true);
    });
  });

  describe("Output format", () => {
    it("should output valid GitHub Actions matrix format", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
      };

      const matrix = generateMatrix(config);

      expect(matrix).toHaveProperty("include");
      expect(Array.isArray(matrix.include)).toBe(true);
    });

    it("should stringify to valid JSON", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        maxParallel: 2,
      };

      const matrix = generateMatrix(config);
      const json = JSON.stringify(matrix);

      expect(() => JSON.parse(json)).not.toThrow();
      const parsed = JSON.parse(json);
      expect(parsed.include).toBeDefined();
      expect(parsed["max-parallel"]).toBe(2);
    });
  });

  describe("Edge cases", () => {
    it("should handle config with no arrays (empty matrix)", () => {
      const config: MatrixConfig = {};

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(0);
    });

    it("should preserve property names in output", () => {
      const config: MatrixConfig = {
        customOs: ["ubuntu-latest"],
        customVersion: ["1.0"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include[0]).toHaveProperty("customOs");
      expect(matrix.include[0]).toHaveProperty("customVersion");
    });

    it("should handle special characters in values", () => {
      const config: MatrixConfig = {
        os: ["ubuntu-latest", "windows-2022"],
        tag: ["v1.0.0", "feature/test-branch"],
      };

      const matrix = generateMatrix(config);

      expect(matrix.include.length).toBe(4);
      expect(
        matrix.include.some((m) => m.tag === "feature/test-branch")
      ).toBe(true);
    });
  });
});
