/**
 * Environment matrix generator.
 *
 * Given a configuration describing OS options, language versions and feature
 * flags, this module produces a build matrix suitable for a GitHub Actions
 * `strategy.matrix`. It supports include/exclude rules, `max-parallel` limits,
 * `fail-fast` configuration and validation of a maximum matrix size.
 */

/** A single concrete combination in the matrix (one job). */
export type MatrixCombination = Record<string, string | number | boolean>;

/** Thrown when the generated matrix exceeds the configured `maxSize`. */
export class MatrixSizeError extends Error {
  constructor(
    readonly actual: number,
    readonly maximum: number,
  ) {
    super(
      `Generated matrix has ${actual} combinations, which exceeds the ` +
        `maximum allowed size of ${maximum}.`,
    );
    this.name = "MatrixSizeError";
  }
}

/** Thrown when the input configuration is invalid. */
export class MatrixConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixConfigError";
  }
}

/** Input configuration describing the dimensions and rules of the matrix. */
export interface MatrixConfig {
  /** Operating systems to build on (e.g. "ubuntu-latest"). */
  os: string[];
  /** Language/runtime versions (e.g. "18", "20"). */
  language: string[];
  /** Optional feature flags; each becomes a `feature` axis value. */
  features?: string[];
  /** Extra combinations / keys to add (GitHub Actions `include` semantics). */
  include?: MatrixCombination[];
  /** Combinations to remove (GitHub Actions `exclude` semantics). */
  exclude?: MatrixCombination[];
  /** Maximum number of jobs run concurrently. */
  maxParallel?: number;
  /** Whether to cancel in-progress jobs when one fails. */
  failFast?: boolean;
  /** Hard cap on the number of generated combinations. */
  maxSize?: number;
}

/** The `strategy` object emitted for consumption by GitHub Actions. */
export interface StrategyOutput {
  matrix: {
    include: MatrixCombination[];
  };
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}

/**
 * Build the cartesian product of the named axes. Each axis with at least one
 * value multiplies the number of combinations; empty/absent axes are skipped.
 */
function cartesianProduct(
  axes: Array<{ key: string; values: Array<string | number | boolean> }>,
): MatrixCombination[] {
  // Seed with a single empty combination, then fold each axis over the result.
  let combos: MatrixCombination[] = [{}];
  for (const axis of axes) {
    if (axis.values.length === 0) continue;
    const next: MatrixCombination[] = [];
    for (const combo of combos) {
      for (const value of axis.values) {
        next.push({ ...combo, [axis.key]: value });
      }
    }
    combos = next;
  }
  return combos;
}

/** The axis keys that participate in the cartesian product. */
const AXIS_KEYS = ["os", "language", "feature"] as const;

/**
 * Does `entry` match `combo`? A match means every key present in `entry` is also
 * present in `combo` with an equal value (partial / subset matching, exactly how
 * GitHub Actions evaluates `exclude` entries).
 */
function matches(combo: MatrixCombination, entry: MatrixCombination): boolean {
  return Object.entries(entry).every(([key, value]) => combo[key] === value);
}

/**
 * Apply `include` entries using GitHub Actions semantics:
 *  - An include is merged into every existing combination whose *axis* values it
 *    agrees with (keys not present in the include, or non-axis keys, never block
 *    a match).
 *  - If an include matches no combination, it is appended as a brand-new one.
 */
function applyIncludes(
  combos: MatrixCombination[],
  includes: MatrixCombination[],
): MatrixCombination[] {
  const result = combos.map((c) => ({ ...c }));
  for (const inc of includes) {
    // Only the axis keys of the include can disqualify a combination.
    const axisConstraints = Object.entries(inc).filter(([k]) =>
      (AXIS_KEYS as readonly string[]).includes(k),
    );
    let matched = false;
    for (const combo of result) {
      const agrees = axisConstraints.every(([k, v]) => combo[k] === v);
      if (agrees) {
        Object.assign(combo, inc);
        matched = true;
      }
    }
    if (!matched) result.push({ ...inc });
  }
  return result;
}

/** Validate the input configuration, throwing MatrixConfigError on problems. */
function validateConfig(config: MatrixConfig): void {
  if (!Array.isArray(config.os) || config.os.length === 0) {
    throw new MatrixConfigError("`os` must be a non-empty array of OS names.");
  }
  if (!Array.isArray(config.language) || config.language.length === 0) {
    throw new MatrixConfigError(
      "`language` must be a non-empty array of language versions.",
    );
  }
  if (
    config.maxParallel !== undefined &&
    (!Number.isInteger(config.maxParallel) || config.maxParallel < 1)
  ) {
    throw new MatrixConfigError("`maxParallel` must be a positive integer.");
  }
  if (
    config.maxSize !== undefined &&
    (!Number.isInteger(config.maxSize) || config.maxSize < 1)
  ) {
    throw new MatrixConfigError("`maxSize` must be a positive integer.");
  }
}

/**
 * Generate the full build matrix from a configuration.
 */
export function generateMatrix(config: MatrixConfig): StrategyOutput {
  validateConfig(config);

  const axes: Array<{ key: string; values: Array<string | number | boolean> }> = [
    { key: "os", values: config.os },
    { key: "language", values: config.language },
  ];
  if (config.features && config.features.length > 0) {
    axes.push({ key: "feature", values: config.features });
  }

  // 1. Cartesian product of all axes.
  let combinations = cartesianProduct(axes);

  // 2. Remove combinations matching any exclude rule (partial match).
  if (config.exclude && config.exclude.length > 0) {
    combinations = combinations.filter(
      (combo) => !config.exclude!.some((ex) => matches(combo, ex)),
    );
  }

  // 3. Apply include rules (augment existing combos or append new ones).
  if (config.include && config.include.length > 0) {
    combinations = applyIncludes(combinations, config.include);
  }

  // 4. Validate the resulting size against the configured maximum.
  if (config.maxSize !== undefined && combinations.length > config.maxSize) {
    throw new MatrixSizeError(combinations.length, config.maxSize);
  }

  const output: StrategyOutput = { matrix: { include: combinations } };
  if (config.maxParallel !== undefined) output["max-parallel"] = config.maxParallel;
  if (config.failFast !== undefined) output["fail-fast"] = config.failFast;
  return output;
}
