import { describe, it, expect } from "bun:test";
import { generateMatrix, serializeMatrixJSON } from "./matrix";

describe("Matrix Generator", () => {
  describe("Basic matrix generation", () => {
    it("should generate a simple matrix from os and node versions", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        nodeVersion: ["18", "20"],
      };

      const result = generateMatrix(config);

      expect(result).toBeDefined();
      expect(result.matrix).toBeDefined();
      expect(result.matrix.include).toBeDefined();
      expect(Array.isArray(result.matrix.include)).toBe(true);
      expect(result.matrix.include.length).toBe(4);
    });

    it("should include all combinations of os and nodeVersion", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        nodeVersion: ["18", "20"],
      };

      const result = generateMatrix(config);

      expect(result.matrix.include).toContainEqual({
        os: "ubuntu-latest",
        nodeVersion: "18",
      });
      expect(result.matrix.include).toContainEqual({
        os: "ubuntu-latest",
        nodeVersion: "20",
      });
      expect(result.matrix.include).toContainEqual({
        os: "macos-latest",
        nodeVersion: "18",
      });
      expect(result.matrix.include).toContainEqual({
        os: "macos-latest",
        nodeVersion: "20",
      });
    });
  });

  describe("Exclude rules", () => {
    it("should include exclude rules in output", () => {
      const config = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18", "20"],
        excludeRules: [{ os: "ubuntu-latest", nodeVersion: "18" }],
      };

      const result = generateMatrix(config);

      expect(result.matrix.exclude).toBeDefined();
      expect(result.matrix.exclude).toContainEqual({
        os: "ubuntu-latest",
        nodeVersion: "18",
      });
    });
  });

  describe("Configuration options", () => {
    it("should include maxParallel when specified", () => {
      const config = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        maxParallel: 5,
      };

      const result = generateMatrix(config);

      expect(result.maxParallel).toBe(5);
    });

    it("should include failFast when specified", () => {
      const config = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        failFast: true,
      };

      const result = generateMatrix(config);

      expect(result.failFast).toBe(true);
    });
  });

  describe("Matrix size validation", () => {
    it("should reject matrices exceeding max size", () => {
      const config = {
        os: Array.from({ length: 100 }, (_, i) => `os-${i}`),
        nodeVersion: Array.from({ length: 100 }, (_, i) => `node-${i}`),
        maxSize: 1000,
      };

      expect(() => {
        generateMatrix(config as any);
      }).toThrow();
    });

    it("should use default max size of 256 if not specified", () => {
      const config = {
        os: Array.from({ length: 20 }, (_, i) => `os-${i}`),
        nodeVersion: Array.from({ length: 15 }, (_, i) => `node-${i}`),
      };

      expect(() => {
        generateMatrix(config);
      }).toThrow("exceeds maximum allowed size 256");
    });
  });

  describe("JSON serialization", () => {
    it("should serialize matrix to valid JSON", () => {
      const config = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
      };

      const result = generateMatrix(config);
      const json = serializeMatrixJSON(result);

      expect(typeof json).toBe("string");
      const parsed = JSON.parse(json);
      expect(parsed.matrix).toBeDefined();
      expect(parsed.matrix.include).toBeDefined();
    });

    it("should include all matrix properties in JSON", () => {
      const config = {
        os: ["ubuntu-latest"],
        nodeVersion: ["18"],
        maxParallel: 5,
        failFast: true,
        excludeRules: [{ os: "ubuntu-latest", nodeVersion: "18" }],
      };

      const result = generateMatrix(config);
      const json = serializeMatrixJSON(result);
      const parsed = JSON.parse(json);

      expect(parsed.maxParallel).toBe(5);
      expect(parsed.failFast).toBe(true);
      expect(parsed.matrix.exclude).toBeDefined();
    });
  });

  describe("Edge cases", () => {
    it("should handle empty configuration", () => {
      const config = {};
      const result = generateMatrix(config);

      expect(result.matrix.include.length).toBe(0);
    });

    it("should handle single os", () => {
      const config = {
        os: ["ubuntu-latest"],
      };

      const result = generateMatrix(config);

      expect(result.matrix.include.length).toBe(1);
      expect(result.matrix.include[0]).toEqual({ os: "ubuntu-latest" });
    });

    it("should handle multiple exclude rules", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        nodeVersion: ["18", "20"],
        excludeRules: [
          { os: "ubuntu-latest", nodeVersion: "18" },
          { os: "macos-latest", nodeVersion: "20" },
        ],
      };

      const result = generateMatrix(config);

      expect(result.matrix.exclude?.length).toBe(2);
    });
  });
});
