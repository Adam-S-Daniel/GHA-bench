import { describe, it, expect } from "bun:test";
import { generateMatrix } from "./matrix";

describe("Environment Matrix Generator", () => {
  describe("Basic matrix generation", () => {
    it("should generate a basic matrix from OS and language options", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
      };

      const result = generateMatrix(config);

      expect(result).toBeDefined();
      expect(result.include).toBeDefined();
      expect(Array.isArray(result.include)).toBe(true);
      expect(result.include.length).toBe(4); // 2 OS × 2 node versions
    });

    it("should generate correct combinations in cartesian product", () => {
      const config = {
        os: ["ubuntu"],
        node: ["18", "20"],
      };

      const result = generateMatrix(config);

      expect(result.include).toEqual([
        { os: "ubuntu", node: "18" },
        { os: "ubuntu", node: "20" },
      ]);
    });

    it("should handle single values in all dimensions", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(1);
      expect(result.include[0]).toEqual({
        os: "ubuntu-latest",
        node: "20",
      });
    });

    it("should handle multiple dimensions (3+ axes)", () => {
      const config = {
        os: ["ubuntu", "macos"],
        node: ["18", "20"],
        python: ["3.8", "3.9"],
      };

      const result = generateMatrix(config);

      // 2 × 2 × 2 = 8 combinations
      expect(result.include.length).toBe(8);
    });
  });

  describe("Include rules", () => {
    it("should respect include rules", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        include: [{ os: "windows-latest", node: "20" }],
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(5); // 4 base + 1 include
      const windowsEntry = result.include.find(
        (e: any) => e.os === "windows-latest"
      );
      expect(windowsEntry).toBeDefined();
    });

    it("should add multiple include entries", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
        include: [
          { os: "windows-latest", node: "20", extra: "value1" },
          { os: "macos-latest", node: "18", extra: "value2" },
        ],
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(3); // 1 base + 2 include
    });

    it("should preserve include entry properties", () => {
      const config = {
        os: ["ubuntu"],
        node: ["20"],
        include: [{ os: "custom", node: "20", custom_prop: "test_value" }],
      };

      const result = generateMatrix(config);

      const customEntry = result.include.find(
        (e: any) => e.custom_prop === "test_value"
      );
      expect(customEntry).toBeDefined();
      expect(customEntry!.custom_prop).toBe("test_value");
    });
  });

  describe("Exclude rules", () => {
    it("should respect exclude rules", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        exclude: [{ os: "macos-latest", node: "18" }],
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(3); // 4 base - 1 exclude
    });

    it("should exclude multiple entries matching rule", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        exclude: [{ node: "18" }], // Exclude all with node 18
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(2); // Only 20 versions remain
      result.include.forEach((combo: any) => {
        expect(combo.node).toBe("20");
      });
    });

    it("should handle multiple exclude rules", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        exclude: [
          { os: "macos-latest", node: "18" },
          { os: "ubuntu-latest", node: "20" },
        ],
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBe(2);
    });

    it("should include exclude field in output", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
        exclude: [{ os: "windows", node: "18" }],
      };

      const result = generateMatrix(config);

      expect(result.exclude).toBeDefined();
      expect(result.exclude).toEqual([{ os: "windows", node: "18" }]);
    });
  });

  describe("Configuration options", () => {
    it("should apply max-parallel limit", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        "max-parallel": 2,
      };

      const result = generateMatrix(config);

      expect(result["max-parallel"]).toBe(2);
    });

    it("should apply fail-fast = true", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
        "fail-fast": true,
      };

      const result = generateMatrix(config);

      expect(result["fail-fast"]).toBe(true);
    });

    it("should apply fail-fast = false", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
        "fail-fast": false,
      };

      const result = generateMatrix(config);

      expect(result["fail-fast"]).toBe(false);
    });

    it("should not include unset optional configuration", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
      };

      const result = generateMatrix(config);

      expect(result["max-parallel"]).toBeUndefined();
      expect(result["fail-fast"]).toBeUndefined();
    });

    it("should combine multiple configuration options", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: ["20"],
        "max-parallel": 3,
        "fail-fast": false,
      };

      const result = generateMatrix(config);

      expect(result["max-parallel"]).toBe(3);
      expect(result["fail-fast"]).toBe(false);
    });
  });

  describe("Size validation", () => {
    it("should validate matrix does not exceed maximum size", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest", "windows-latest"],
        node: ["16", "18", "20"],
        maxSize: 10,
      };

      const result = generateMatrix(config);

      expect(result.include.length).toBeLessThanOrEqual(10);
    });

    it("should throw error if matrix exceeds maximum size", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest", "windows-latest"],
        node: ["16", "18", "20"],
        python: ["3.8", "3.9", "3.10"],
        maxSize: 5, // 3×3×3 = 27, exceeds 5
      };

      expect(() => generateMatrix(config)).toThrow();
    });

    it("should throw with detailed size message", () => {
      const config = {
        os: ["a", "b"],
        node: ["1", "2"],
        maxSize: 3,
      };

      try {
        generateMatrix(config);
        expect(true).toBe(false); // Should not reach here
      } catch (e: any) {
        expect(e.message).toContain("Matrix size");
        expect(e.message).toContain("4");
        expect(e.message).toContain("3");
      }
    });
  });

  describe("Error handling", () => {
    it("should handle empty arrays gracefully", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: [],
      };

      expect(() => generateMatrix(config)).toThrow();
    });

    it("should throw error for non-array matrix axis", () => {
      const config = {
        os: ["ubuntu-latest"],
        node: "20",
      } as any;

      expect(() => generateMatrix(config)).toThrow();
    });

    it("should identify which axis is empty", () => {
      const config = {
        os: ["ubuntu"],
        node: [],
      };

      try {
        generateMatrix(config);
        expect(true).toBe(false);
      } catch (e: any) {
        expect(e.message).toContain("node");
      }
    });
  });

  describe("Complex scenarios", () => {
    it("should combine includes, excludes, and config options", () => {
      const config = {
        os: ["ubuntu-latest", "macos-latest"],
        node: ["18", "20"],
        include: [{ os: "windows-latest", node: "20" }],
        exclude: [{ os: "macos-latest", node: "18" }],
        "max-parallel": 4,
        "fail-fast": true,
      };

      const result = generateMatrix(config);

      // 2×2 = 4, minus 1 exclude = 3, plus 1 include = 4
      expect(result.include.length).toBe(4);
      expect(result["max-parallel"]).toBe(4);
      expect(result["fail-fast"]).toBe(true);
    });

    it("should handle include that duplicates existing entry", () => {
      const config = {
        os: ["ubuntu"],
        node: ["20"],
        include: [{ os: "ubuntu", node: "20" }],
      };

      const result = generateMatrix(config);

      // Should have both - one from cartesian, one from include
      expect(result.include.length).toBe(2);
    });
  });
});
