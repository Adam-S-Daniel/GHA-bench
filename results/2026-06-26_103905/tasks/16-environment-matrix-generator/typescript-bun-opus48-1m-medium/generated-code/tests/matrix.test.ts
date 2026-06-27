import { describe, expect, test } from "bun:test";
import { generateMatrix, MatrixSizeError } from "../src/matrix";

// --- Cycle 1: basic cartesian product of OS x language ------------------------
describe("generateMatrix - cartesian product", () => {
  test("produces the cartesian product of os and language", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "windows-latest"],
      language: ["18", "20"],
    });

    // The expanded combinations live under matrix.include (the canonical way to
    // feed a dynamically-generated matrix into GitHub Actions via fromJSON).
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "18" },
      { os: "ubuntu-latest", language: "20" },
      { os: "windows-latest", language: "18" },
      { os: "windows-latest", language: "20" },
    ]);
  });
});

// --- Cycle 2: feature flags add a third axis ---------------------------------
describe("generateMatrix - feature axis", () => {
  test("adds a feature axis when features are provided", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      language: ["20"],
      features: ["sqlite", "postgres"],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "20", feature: "sqlite" },
      { os: "ubuntu-latest", language: "20", feature: "postgres" },
    ]);
  });
});

// --- Cycle 3: exclude rules remove matching combinations ---------------------
describe("generateMatrix - exclude rules", () => {
  test("removes combinations matching an exclude entry (partial match)", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "windows-latest"],
      language: ["18", "20"],
      exclude: [{ os: "windows-latest", language: "18" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "18" },
      { os: "ubuntu-latest", language: "20" },
      { os: "windows-latest", language: "20" },
    ]);
  });

  test("a partial exclude removes every matching combination", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "windows-latest"],
      language: ["18", "20"],
      exclude: [{ os: "windows-latest" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "18" },
      { os: "ubuntu-latest", language: "20" },
    ]);
  });
});

// --- Cycle 4: include rules (GitHub semantics) -------------------------------
describe("generateMatrix - include rules", () => {
  test("an include with only extra keys augments every combination", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      language: ["18", "20"],
      include: [{ color: "green" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "18", color: "green" },
      { os: "ubuntu-latest", language: "20", color: "green" },
    ]);
  });

  test("an include matching an axis value augments only those combinations", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "windows-latest"],
      language: ["20"],
      include: [{ os: "windows-latest", npm: "6" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "20" },
      { os: "windows-latest", language: "20", npm: "6" },
    ]);
  });

  test("an include that matches nothing is appended as a new combination", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      language: ["20"],
      include: [{ os: "macos-latest", language: "21" }],
    });
    expect(result.matrix.include).toEqual([
      { os: "ubuntu-latest", language: "20" },
      { os: "macos-latest", language: "21" },
    ]);
  });
});

// --- Cycle 5: max-parallel and fail-fast pass through ------------------------
describe("generateMatrix - strategy options", () => {
  test("emits max-parallel and fail-fast when provided", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      language: ["20"],
      maxParallel: 2,
      failFast: false,
    });
    expect(result["max-parallel"]).toBe(2);
    expect(result["fail-fast"]).toBe(false);
  });

  test("omits strategy options when not provided", () => {
    const result = generateMatrix({ os: ["ubuntu-latest"], language: ["20"] });
    expect(result).not.toHaveProperty("max-parallel");
    expect(result).not.toHaveProperty("fail-fast");
  });
});

// --- Cycle 6: maxSize validation ---------------------------------------------
describe("generateMatrix - size validation", () => {
  test("throws a MatrixSizeError when the matrix exceeds maxSize", () => {
    expect(() =>
      generateMatrix({
        os: ["a", "b", "c"],
        language: ["1", "2", "3"],
        maxSize: 4,
      }),
    ).toThrow(MatrixSizeError);
  });

  test("the error message reports the actual and maximum sizes", () => {
    try {
      generateMatrix({ os: ["a", "b"], language: ["1", "2"], maxSize: 2 });
      throw new Error("expected generateMatrix to throw");
    } catch (err) {
      expect(err).toBeInstanceOf(MatrixSizeError);
      expect((err as Error).message).toContain("4");
      expect((err as Error).message).toContain("2");
    }
  });

  test("does not throw when the matrix is within maxSize", () => {
    expect(() =>
      generateMatrix({ os: ["a", "b"], language: ["1"], maxSize: 5 }),
    ).not.toThrow();
  });
});

// --- Cycle 7: input validation -----------------------------------------------
describe("generateMatrix - input validation", () => {
  test("throws a clear error when os is missing or empty", () => {
    expect(() => generateMatrix({ os: [], language: ["20"] })).toThrow(
      /os.*non-empty/i,
    );
  });

  test("throws a clear error when language is missing or empty", () => {
    expect(() => generateMatrix({ os: ["ubuntu-latest"], language: [] })).toThrow(
      /language.*non-empty/i,
    );
  });
});
