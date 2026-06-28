// TDD: RED step #1.
// The very first behaviour we need is expanding the named matrix axes
// (os / language / features) into the full cartesian product of
// combinations, exactly as GitHub Actions does for strategy.matrix.
//
// We import from a module that does not exist yet, so this test fails to
// even compile/import -> RED. We then write the minimum code to go GREEN.
import { test, expect } from "bun:test";
import { generateMatrix, parseConfig, MatrixSizeError, MatrixConfigError } from "./matrix-generator";

test("expands named axes into the full cartesian product", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["18", "20"],
  });

  // 2 OS * 2 language versions = 4 combinations
  expect(result.count).toBe(4);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18" },
    { os: "ubuntu-latest", language: "20" },
    { os: "windows-latest", language: "18" },
    { os: "windows-latest", language: "20" },
  ]);
});

// TDD: RED step #2 — exclude rules.
// An exclude entry removes every combination that matches ALL of its
// key:value pairs (a partial match against the combination), mirroring
// GitHub Actions' `matrix.exclude` semantics.
test("exclude removes combinations matching all of an exclude entry's pairs", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["18", "20"],
    exclude: [{ os: "windows-latest", language: "18" }],
  });

  expect(result.count).toBe(3);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18" },
    { os: "ubuntu-latest", language: "20" },
    { os: "windows-latest", language: "20" },
  ]);
});

test("a partial exclude entry removes every matching combination", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["18", "20"],
    // Only `os` specified -> removes BOTH windows combinations.
    exclude: [{ os: "windows-latest" }],
  });

  expect(result.count).toBe(2);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18" },
    { os: "ubuntu-latest", language: "20" },
  ]);
});

// TDD: RED step #3 — include rules (GitHub Actions semantics).
//
// For each include object: add its key:value pairs to every existing
// combination that does NOT overwrite an original matrix axis value. If it
// cannot be added to ANY combination, append it as a brand-new combination.
test("include extends matching combinations with extra keys", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["18", "20"],
    // Adds `experimental: true` only to the windows+20 combination.
    include: [{ os: "windows-latest", language: "20", experimental: true }],
  });

  expect(result.count).toBe(4);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18" },
    { os: "ubuntu-latest", language: "20" },
    { os: "windows-latest", language: "18" },
    { os: "windows-latest", language: "20", experimental: true },
  ]);
});

test("include adds an extra key to multiple matching combinations", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["18", "20"],
    // Matches both language:18 combinations (partial match on language).
    include: [{ language: "18", lts: true }],
  });

  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18", lts: true },
    { os: "ubuntu-latest", language: "20" },
    { os: "windows-latest", language: "18", lts: true },
    { os: "windows-latest", language: "20" },
  ]);
});

test("include that overwrites an original axis value becomes a new combination", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest"],
    language: ["18", "20"],
    // os:macos-latest is not an original axis value here, so this entry
    // cannot extend any existing combination -> appended as new.
    include: [{ os: "macos-latest", language: "22" }],
  });

  expect(result.count).toBe(3);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "18" },
    { os: "ubuntu-latest", language: "20" },
    { os: "macos-latest", language: "22" },
  ]);
});

test("include with only new keys is added to every combination", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    // No keys overlap with any axis -> added to all combinations.
    include: [{ color: "green" }],
  });

  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", color: "green" },
    { os: "windows-latest", color: "green" },
  ]);
});

// TDD: RED step #4 — third axis (features) participates in the product.
test("features axis participates in the cartesian product", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest"],
    language: ["20"],
    features: ["minimal", "full"],
  });

  expect(result.count).toBe(2);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", language: "20", features: "minimal" },
    { os: "ubuntu-latest", language: "20", features: "full" },
  ]);
});

// TDD: RED step #5 — the GitHub-Actions-ready strategy block.
test("builds a strategy block with fail-fast, max-parallel and matrix", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest", "windows-latest"],
    language: ["20"],
    failFast: false,
    maxParallel: 2,
  });

  expect(result.strategy["fail-fast"]).toBe(false);
  expect(result.strategy["max-parallel"]).toBe(2);
  expect(result.strategy.matrix.os).toEqual(["ubuntu-latest", "windows-latest"]);
  expect(result.strategy.matrix.language).toEqual(["20"]);
});

test("fail-fast defaults to true and max-parallel is omitted when unset", () => {
  const result = generateMatrix({ os: ["ubuntu-latest"] });
  expect(result.strategy["fail-fast"]).toBe(true);
  expect(result.strategy).not.toHaveProperty("max-parallel");
});

test("strategy.matrix carries include and exclude through to output", () => {
  const result = generateMatrix({
    os: ["ubuntu-latest"],
    language: ["18", "20"],
    include: [{ os: "macos-latest", language: "22" }],
    exclude: [{ language: "18" }],
  });
  expect(result.strategy.matrix.include).toEqual([{ os: "macos-latest", language: "22" }]);
  expect(result.strategy.matrix.exclude).toEqual([{ language: "18" }]);
});

// TDD: RED step #6 — max-size validation.
test("throws MatrixSizeError when the matrix exceeds maxSize", () => {
  expect(() =>
    generateMatrix({
      os: ["a", "b", "c"],
      language: ["1", "2", "3"],
      maxSize: 5, // 3*3 = 9 > 5
    }),
  ).toThrow(MatrixSizeError);
});

test("MatrixSizeError reports the actual and maximum sizes", () => {
  let caught: MatrixSizeError | undefined;
  try {
    generateMatrix({ os: ["a", "b", "c"], language: ["1", "2", "3"], maxSize: 5 });
  } catch (e) {
    caught = e as MatrixSizeError;
  }
  expect(caught).toBeInstanceOf(MatrixSizeError);
  expect(caught!.actual).toBe(9);
  expect(caught!.maxSize).toBe(5);
  expect(caught!.message).toContain("9");
  expect(caught!.message).toContain("5");
});

test("does not throw when matrix is exactly at maxSize", () => {
  expect(() => generateMatrix({ os: ["a", "b"], language: ["1", "2"], maxSize: 4 })).not.toThrow();
});

// TDD: RED step #7 — graceful validation with meaningful messages.
test("throws MatrixConfigError when there are no axes and no include", () => {
  expect(() => generateMatrix({})).toThrow(MatrixConfigError);
  expect(() => generateMatrix({})).toThrow(/at least one/i);
});

test("an include-only matrix (no axes) is valid", () => {
  const result = generateMatrix({ include: [{ os: "ubuntu-latest", language: "20" }] });
  expect(result.count).toBe(1);
  expect(result.combinations).toEqual([{ os: "ubuntu-latest", language: "20" }]);
});

test("multiple include-only entries are each standalone combinations", () => {
  // With no base axes there is nothing to extend, so every include entry must
  // become its own combination (matching GitHub's behaviour) rather than
  // collapsing into a single merged combination.
  const result = generateMatrix({
    include: [
      { os: "ubuntu-latest", arch: "x64" },
      { os: "ubuntu-latest", arch: "arm64" },
    ],
  });
  expect(result.count).toBe(2);
  expect(result.combinations).toEqual([
    { os: "ubuntu-latest", arch: "x64" },
    { os: "ubuntu-latest", arch: "arm64" },
  ]);
});

test("rejects a negative max-parallel", () => {
  expect(() => generateMatrix({ os: ["a"], maxParallel: -1 })).toThrow(MatrixConfigError);
});

test("rejects a non-positive maxSize", () => {
  expect(() => generateMatrix({ os: ["a"], maxSize: 0 })).toThrow(MatrixConfigError);
});

// TDD: RED step #8 — parseConfig validates raw (untyped) JSON input.
test("parseConfig accepts a well-formed object", () => {
  const config = parseConfig({ os: ["ubuntu-latest"], language: ["20"] });
  expect(config.os).toEqual(["ubuntu-latest"]);
});

test("parseConfig rejects a non-object", () => {
  expect(() => parseConfig("not an object")).toThrow(MatrixConfigError);
  expect(() => parseConfig(null)).toThrow(MatrixConfigError);
});

test("parseConfig rejects an axis that is not an array", () => {
  expect(() => parseConfig({ os: "ubuntu-latest" })).toThrow(MatrixConfigError);
  expect(() => parseConfig({ os: "ubuntu-latest" })).toThrow(/os/);
});

test("parseConfig rejects include that is not an array of objects", () => {
  expect(() => parseConfig({ include: "x" })).toThrow(MatrixConfigError);
  expect(() => parseConfig({ os: ["a"], include: ["x"] })).toThrow(MatrixConfigError);
});
