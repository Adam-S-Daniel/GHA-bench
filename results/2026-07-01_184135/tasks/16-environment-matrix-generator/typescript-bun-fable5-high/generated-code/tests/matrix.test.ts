/**
 * Unit tests for the environment matrix generator.
 *
 * TDD approach: each describe block was added as a RED test first, then the
 * minimum implementation in src/matrix.ts was written to turn it GREEN,
 * followed by a refactor pass. See git-less chronology in comments.
 */
import { describe, expect, test } from "bun:test";
import { applyExcludes, applyIncludes, expandCombinations, generateMatrix, MatrixValidationError, validateConfig } from "../src/matrix";

describe("expandCombinations (cycle 1: cartesian product)", () => {
  test("expands os x language-version x feature into all combinations", () => {
    const combos = expandCombinations({
      os: ["ubuntu-latest", "macos-latest"],
      languageVersions: ["18", "20"],
      featureFlags: ["telemetry"],
    });

    expect(combos).toEqual([
      { os: "ubuntu-latest", "language-version": "18", feature: "telemetry" },
      { os: "ubuntu-latest", "language-version": "20", feature: "telemetry" },
      { os: "macos-latest", "language-version": "18", feature: "telemetry" },
      { os: "macos-latest", "language-version": "20", feature: "telemetry" },
    ]);
  });

  test("feature flags are optional — omitting them yields os x version only", () => {
    const combos = expandCombinations({
      os: ["windows-latest"],
      languageVersions: ["3.12"],
    });

    expect(combos).toEqual([{ os: "windows-latest", "language-version": "3.12" }]);
  });
});

describe("applyExcludes (cycle 2: exclude rules)", () => {
  const combos = [
    { os: "ubuntu-latest", "language-version": "18" },
    { os: "ubuntu-latest", "language-version": "20" },
    { os: "macos-latest", "language-version": "18" },
    { os: "macos-latest", "language-version": "20" },
  ];

  test("removes combinations where ALL exclude keys match (partial match)", () => {
    // GitHub semantics: an exclude entry removes any combination that matches
    // every key/value in the entry — unlisted keys match anything.
    const result = applyExcludes(combos, [{ os: "macos-latest" }]);
    expect(result).toEqual([
      { os: "ubuntu-latest", "language-version": "18" },
      { os: "ubuntu-latest", "language-version": "20" },
    ]);
  });

  test("exact exclude removes only the single matching combination", () => {
    const result = applyExcludes(combos, [
      { os: "ubuntu-latest", "language-version": "20" },
    ]);
    expect(result).toHaveLength(3);
    expect(result).not.toContainEqual({ os: "ubuntu-latest", "language-version": "20" });
  });

  test("exclude entry that matches nothing leaves the matrix untouched", () => {
    const result = applyExcludes(combos, [{ os: "windows-latest" }]);
    expect(result).toEqual(combos);
  });
});

describe("applyIncludes (cycle 3: include rules)", () => {
  const original = [
    { os: "ubuntu-latest", "language-version": "18" },
    { os: "ubuntu-latest", "language-version": "20" },
    { os: "macos-latest", "language-version": "20" },
  ];
  const originalKeys = ["os", "language-version"];

  test("include with matching matrix keys merges extra keys into matches only", () => {
    const result = applyIncludes(
      original,
      [{ os: "ubuntu-latest", "experimental": "true" }],
      originalKeys,
    );
    expect(result).toEqual([
      { os: "ubuntu-latest", "language-version": "18", experimental: "true" },
      { os: "ubuntu-latest", "language-version": "20", experimental: "true" },
      { os: "macos-latest", "language-version": "20" },
    ]);
  });

  test("include with only new keys is merged into every combination", () => {
    const result = applyIncludes(original, [{ cache: "npm" }], originalKeys);
    expect(result.every((c) => c.cache === "npm")).toBe(true);
    expect(result).toHaveLength(3);
  });

  test("include that matches no combination is appended as a new combination", () => {
    const result = applyIncludes(
      original,
      [{ os: "windows-latest", "language-version": "22" }],
      originalKeys,
    );
    expect(result).toHaveLength(4);
    expect(result[3]).toEqual({ os: "windows-latest", "language-version": "22" });
  });
});

describe("generateMatrix (cycle 4: full strategy assembly)", () => {
  test("produces a complete strategy object with fail-fast, max-parallel and expanded matrix", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest", "macos-latest"],
      languageVersions: ["18", "20"],
      featureFlags: ["telemetry"],
      exclude: [{ os: "macos-latest", "language-version": "18" }],
      include: [{ os: "ubuntu-latest", experimental: "true" }],
      maxParallel: 2,
      failFast: false,
    });

    expect(result.jobCount).toBe(3);
    expect(result.strategy).toEqual({
      "fail-fast": false,
      "max-parallel": 2,
      matrix: {
        include: [
          { os: "ubuntu-latest", "language-version": "18", feature: "telemetry", experimental: "true" },
          { os: "ubuntu-latest", "language-version": "20", feature: "telemetry", experimental: "true" },
          { os: "macos-latest", "language-version": "20", feature: "telemetry" },
        ],
      },
    });
  });

  test("defaults: fail-fast true, no max-parallel key when not configured", () => {
    const result = generateMatrix({ os: ["ubuntu-latest"], languageVersions: ["20"] });
    expect(result.strategy["fail-fast"]).toBe(true);
    expect("max-parallel" in result.strategy).toBe(false);
    expect(result.jobCount).toBe(1);
  });

  test("include-only new combination counts toward jobCount", () => {
    const result = generateMatrix({
      os: ["ubuntu-latest"],
      languageVersions: ["20"],
      include: [{ os: "windows-latest", "language-version": "22" }],
    });
    expect(result.jobCount).toBe(2);
  });
});

describe("validation (cycle 5: config errors and size limit)", () => {
  test("rejects a config with missing or empty os", () => {
    expect(() => validateConfig({ languageVersions: ["20"] })).toThrow(
      MatrixValidationError,
    );
    expect(() => validateConfig({ os: [], languageVersions: ["20"] })).toThrow(
      '"os" must be a non-empty array',
    );
  });

  test("rejects empty languageVersions with a meaningful message", () => {
    expect(() => validateConfig({ os: ["ubuntu-latest"], languageVersions: [] })).toThrow(
      '"languageVersions" must be a non-empty array',
    );
  });

  test("rejects non-object input and bad option types", () => {
    expect(() => validateConfig("nope")).toThrow("must be a JSON object");
    expect(() =>
      validateConfig({ os: ["u"], languageVersions: ["20"], maxParallel: 0 }),
    ).toThrow('"maxParallel" must be a positive integer');
    expect(() =>
      validateConfig({ os: ["u"], languageVersions: ["20"], failFast: "yes" }),
    ).toThrow('"failFast" must be a boolean');
    expect(() =>
      validateConfig({ os: ["u"], languageVersions: ["20"], exclude: [42] }),
    ).toThrow('"exclude[0]" must be an object');
  });

  test("numeric version values are coerced to strings", () => {
    const config = validateConfig({ os: ["ubuntu-latest"], languageVersions: [18, 20] });
    expect(config.languageVersions).toEqual(["18", "20"]);
  });

  test("generateMatrix enforces the configured maxSize", () => {
    expect(() =>
      generateMatrix({
        os: ["a", "b"],
        languageVersions: ["1", "2"],
        maxSize: 3,
      }),
    ).toThrow("Matrix size 4 exceeds the maximum allowed size 3");
  });

  test("generateMatrix enforces GitHub's 256-job default limit", () => {
    const os = Array.from({ length: 16 }, (_, i) => `os-${i}`);
    const versions = Array.from({ length: 16 }, (_, i) => `v${i}`);
    // 16 x 16 = 256 is fine; one extra include pushes it to 257.
    expect(() => generateMatrix({ os, languageVersions: versions })).not.toThrow();
    expect(() =>
      generateMatrix({
        os,
        languageVersions: versions,
        include: [{ os: "extra", "language-version": "v99" }],
      }),
    ).toThrow("Matrix size 257 exceeds the maximum allowed size 256");
  });
});
