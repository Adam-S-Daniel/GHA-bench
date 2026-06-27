// matrix-generator.ts
//
// Core library for generating a GitHub Actions `strategy.matrix` build matrix
// from a declarative configuration. Built incrementally with red/green TDD.
//
// Step #1 (GREEN): expand the named axes into the full cartesian product.

/** A scalar value allowed inside a matrix combination. */
export type MatrixValue = string | number | boolean;

/** A single fully-resolved combination, e.g. { os: "ubuntu-latest", language: "20" }. */
export type Combination = Record<string, MatrixValue>;

/** The matrix sub-block of a GitHub Actions strategy. */
export interface StrategyMatrix {
  [axis: string]: MatrixValue[] | Combination[] | undefined;
  include?: Combination[];
  exclude?: Combination[];
}

/** A GitHub Actions `jobs.<id>.strategy` object. */
export interface Strategy {
  "fail-fast": boolean;
  "max-parallel"?: number;
  matrix: StrategyMatrix;
}

/** Result of expanding a matrix configuration. */
export interface MatrixResult {
  /** GitHub-Actions-ready strategy block (drop straight into a workflow). */
  strategy: Strategy;
  /** Fully expanded list of build combinations (after exclude/include rules). */
  combinations: Combination[];
  /** Number of combinations (== combinations.length). */
  count: number;
}

/**
 * Thrown when the expanded matrix has more combinations than `maxSize` allows.
 * Carries the offending sizes so callers can render a meaningful message.
 */
export class MatrixSizeError extends Error {
  constructor(
    public readonly actual: number,
    public readonly maxSize: number,
  ) {
    super(
      `Matrix has ${actual} combinations, which exceeds the maximum of ${maxSize}. ` +
        `Reduce the number of axis values, add exclude rules, or raise maxSize.`,
    );
    this.name = "MatrixSizeError";
  }
}

/** Declarative matrix configuration (the input to {@link generateMatrix}). */
export interface MatrixConfig {
  /** Operating system axis. */
  os?: MatrixValue[];
  /** Language / runtime version axis. */
  language?: MatrixValue[];
  /** Feature-flag axis. */
  features?: MatrixValue[];
  /** Combinations to remove (partial match against expanded combinations). */
  exclude?: Combination[];
  /** Combinations to add/extend (GitHub Actions `matrix.include` semantics). */
  include?: Combination[];
  /** Limit on concurrently-running jobs (GitHub `strategy.max-parallel`). */
  maxParallel?: number;
  /** Whether to cancel in-progress jobs if any matrix job fails (default true). */
  failFast?: boolean;
  /** Hard cap on the number of expanded combinations (default 256, GitHub's limit). */
  maxSize?: number;
}

/** GitHub Actions itself caps a matrix at 256 combinations. */
export const DEFAULT_MAX_SIZE = 256;

/** Thrown when the configuration is structurally invalid. */
export class MatrixConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixConfigError";
  }
}

/**
 * Return true if `combo` matches `pattern`: every key in `pattern` is present
 * in `combo` with an equal value. Extra keys in `combo` are ignored, so a
 * partial pattern (e.g. just `{ os }`) matches many combinations.
 */
function matchesPattern(combo: Combination, pattern: Combination): boolean {
  return Object.keys(pattern).every((key) => combo[key] === pattern[key]);
}

/** Remove every combination matching any exclude entry. */
function applyExclude(combinations: Combination[], excludes: Combination[]): Combination[] {
  if (excludes.length === 0) return combinations;
  return combinations.filter(
    (combo) => !excludes.some((pattern) => matchesPattern(combo, pattern)),
  );
}

/**
 * Compute the cartesian product of a set of named axes, preserving the order
 * in which axes are declared and the order of values within each axis. This
 * matches GitHub Actions' expansion order (first axis varies slowest).
 */
function cartesianProduct(axes: Record<string, MatrixValue[]>): Combination[] {
  const keys = Object.keys(axes);
  // With no axes there are no base combinations at all (an include-only matrix
  // relies on this so each include entry becomes a standalone combination,
  // rather than everything merging into one empty seed combination).
  if (keys.length === 0) return [];
  // Seed with a single empty combination, then fan out over each axis.
  let combinations: Combination[] = [{}];
  for (const key of keys) {
    const values = axes[key];
    const next: Combination[] = [];
    for (const combo of combinations) {
      for (const value of values) {
        next.push({ ...combo, [key]: value });
      }
    }
    combinations = next;
  }
  return combinations;
}

/**
 * Collect the declared named axes (os/language/features) into an ordered
 * axis map, skipping any axis that is absent or empty.
 */
function collectAxes(config: MatrixConfig): Record<string, MatrixValue[]> {
  const axes: Record<string, MatrixValue[]> = {};
  for (const key of ["os", "language", "features"] as const) {
    const values = config[key];
    if (values && values.length > 0) {
      axes[key] = values;
    }
  }
  return axes;
}

/**
 * Apply GitHub Actions `include` semantics.
 *
 * For each include entry, in order:
 *  - It can extend an expanded combination only if it does NOT overwrite any
 *    of that combination's ORIGINAL axis values (non-axis keys may differ).
 *  - It is added to every combination it can extend.
 *  - If it cannot extend ANY combination, it is appended as a brand-new
 *    standalone combination.
 *
 * Only the original cartesian-product combinations are eligible for
 * extension; combinations created by earlier include entries are not.
 */
function applyInclude(
  combinations: Combination[],
  includes: Combination[],
  axisKeys: string[],
): Combination[] {
  if (includes.length === 0) return combinations;

  const axisKeySet = new Set(axisKeys);
  // Mark which entries come from the original expansion (extendable).
  const result: Combination[] = combinations.map((c) => ({ ...c }));
  const originalCount = result.length;

  for (const include of includes) {
    let matched = false;
    for (let i = 0; i < originalCount; i++) {
      const combo = result[i];
      // The include overwrites an original axis value if it sets an axis key
      // to a value different from the combination's current value.
      const overwritesAxis = Object.keys(include).some(
        (key) => axisKeySet.has(key) && combo[key] !== include[key],
      );
      if (overwritesAxis) continue;
      // Eligible: merge the include's keys in (added values may be overwritten).
      result[i] = { ...combo, ...include };
      matched = true;
    }
    if (!matched) {
      // Could not extend any combination -> standalone new combination.
      result.push({ ...include });
    }
  }
  return result;
}

/** True for plain objects (not arrays, not null). */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Validate that a value is an array of plain objects (for include/exclude). */
function assertCombinationArray(value: unknown, field: string): asserts value is Combination[] {
  if (!Array.isArray(value)) {
    throw new MatrixConfigError(`"${field}" must be an array of objects.`);
  }
  value.forEach((entry, i) => {
    if (!isPlainObject(entry)) {
      throw new MatrixConfigError(`"${field}[${i}]" must be an object.`);
    }
  });
}

/**
 * Validate and narrow raw, untrusted input (e.g. parsed JSON) into a
 * {@link MatrixConfig}. Throws {@link MatrixConfigError} with a clear message
 * for any structural problem so the CLI can report it gracefully.
 */
export function parseConfig(raw: unknown): MatrixConfig {
  if (!isPlainObject(raw)) {
    throw new MatrixConfigError("Configuration must be a JSON object.");
  }

  const config: MatrixConfig = {};

  // Validate the three named axes.
  for (const key of ["os", "language", "features"] as const) {
    if (raw[key] === undefined) continue;
    if (!Array.isArray(raw[key])) {
      throw new MatrixConfigError(`Axis "${key}" must be an array of values.`);
    }
    config[key] = raw[key] as MatrixValue[];
  }

  if (raw.include !== undefined) {
    assertCombinationArray(raw.include, "include");
    config.include = raw.include;
  }
  if (raw.exclude !== undefined) {
    assertCombinationArray(raw.exclude, "exclude");
    config.exclude = raw.exclude;
  }

  if (raw.maxParallel !== undefined) {
    if (typeof raw.maxParallel !== "number") {
      throw new MatrixConfigError(`"maxParallel" must be a number.`);
    }
    config.maxParallel = raw.maxParallel;
  }
  if (raw.failFast !== undefined) {
    if (typeof raw.failFast !== "boolean") {
      throw new MatrixConfigError(`"failFast" must be a boolean.`);
    }
    config.failFast = raw.failFast;
  }
  if (raw.maxSize !== undefined) {
    if (typeof raw.maxSize !== "number") {
      throw new MatrixConfigError(`"maxSize" must be a number.`);
    }
    config.maxSize = raw.maxSize;
  }

  return config;
}

/** Validate semantic constraints on an already-typed config. */
function validateConfig(config: MatrixConfig): void {
  const hasAxes = (["os", "language", "features"] as const).some(
    (k) => config[k] && config[k]!.length > 0,
  );
  const hasInclude = (config.include?.length ?? 0) > 0;
  if (!hasAxes && !hasInclude) {
    throw new MatrixConfigError(
      "Configuration must define at least one axis (os/language/features) or an include list.",
    );
  }
  if (config.maxParallel !== undefined && config.maxParallel < 1) {
    throw new MatrixConfigError(`"maxParallel" must be a positive integer, got ${config.maxParallel}.`);
  }
  if (config.maxSize !== undefined && config.maxSize < 1) {
    throw new MatrixConfigError(`"maxSize" must be a positive integer, got ${config.maxSize}.`);
  }
}

/** Generate the expanded build matrix from a configuration. */
export function generateMatrix(config: MatrixConfig): MatrixResult {
  validateConfig(config);
  const axes = collectAxes(config);
  const axisKeys = Object.keys(axes);
  let combinations = cartesianProduct(axes);
  combinations = applyExclude(combinations, config.exclude ?? []);
  combinations = applyInclude(combinations, config.include ?? [], axisKeys);

  // Validate size BEFORE returning so callers never see an over-large matrix.
  const maxSize = config.maxSize ?? DEFAULT_MAX_SIZE;
  if (combinations.length > maxSize) {
    throw new MatrixSizeError(combinations.length, maxSize);
  }

  // Assemble the GitHub-Actions-ready strategy block.
  const matrix: StrategyMatrix = { ...axes };
  if (config.include && config.include.length > 0) matrix.include = config.include;
  if (config.exclude && config.exclude.length > 0) matrix.exclude = config.exclude;

  const strategy: Strategy = {
    "fail-fast": config.failFast ?? true,
    matrix,
  };
  if (config.maxParallel !== undefined) {
    strategy["max-parallel"] = config.maxParallel;
  }

  return { strategy, combinations, count: combinations.length };
}
