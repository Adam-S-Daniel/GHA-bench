// Generates a GitHub Actions "strategy.matrix" JSON payload from a declarative
// config describing dimensions (os / language versions / feature flags),
// include/exclude rules, max-parallel, and fail-fast settings.

/** A single matrix cell: a mapping of dimension name -> chosen value. */
export type MatrixCombination = Record<string, string>;

/** Raw dimensions: dimension name -> list of allowed values. */
export type Dimensions = Record<string, string[]>;

/** Config accepted by generateMatrix. */
export interface MatrixConfig {
  /** e.g. { os: ["ubuntu-latest"], node: ["18", "20"] } */
  dimensions: Dimensions;
  /**
   * Extra combinations to add on top of the cartesian product, or extra keys
   * to merge into rows that already match a partial combination. Mirrors
   * GitHub Actions' own `matrix.include` semantics.
   */
  include?: MatrixCombination[];
  /**
   * Rules that drop matching rows. A row is dropped if it matches every
   * key/value pair in ANY exclude entry (a partial entry acts as a wildcard
   * over unspecified keys).
   */
  exclude?: MatrixCombination[];
  /** Mirrors `strategy.fail-fast`. Defaults to true, matching GitHub Actions. */
  failFast?: boolean;
  /** Mirrors `strategy.max-parallel`. Must be >= 1 when provided. */
  maxParallel?: number;
  /**
   * Caller-defined cap on the number of generated rows. Independent of (and
   * checked in addition to) GitHub Actions' own hard limit of 256.
   */
  maxMatrixSize?: number;
}

/** GitHub Actions rejects any matrix with more than 256 generated jobs. */
export const GITHUB_ACTIONS_MAX_MATRIX_SIZE = 256;

/** The GitHub Actions strategy.matrix shape. */
export interface StrategyMatrix {
  include: MatrixCombination[];
  "fail-fast": boolean;
  "max-parallel"?: number;
}

/** Top-level result returned by generateMatrix. */
export interface MatrixResult {
  matrix: StrategyMatrix;
}

/**
 * Computes the cartesian product of all dimension values, producing one
 * combination object per row.
 */
function cartesianProduct(dimensions: Dimensions): MatrixCombination[] {
  const keys = Object.keys(dimensions);
  if (keys.length === 0) {
    return [];
  }

  let combinations: MatrixCombination[] = [{}];
  for (const key of keys) {
    const values = dimensions[key];
    const next: MatrixCombination[] = [];
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
 * Returns true if `combo` already has every key/value pair present in
 * `partial` (i.e. the partial combination "matches" this row).
 */
function matches(combo: MatrixCombination, partial: MatrixCombination): boolean {
  return Object.entries(partial).every(([key, value]) => combo[key] === value);
}

/**
 * Applies GitHub Actions' `include` semantics: for each include entry, if it
 * shares at least one key with an existing row and all of those shared keys
 * match, the entry's extra keys are merged into that row (every matching row
 * gets the merge). Otherwise the entry is appended as a brand new row.
 */
function applyIncludes(
  combinations: MatrixCombination[],
  includes: MatrixCombination[],
): MatrixCombination[] {
  const result = combinations.map((combo) => ({ ...combo }));

  for (const entry of includes) {
    const dimensionKeys = Object.keys(combinations[0] ?? {});
    const sharedKeys = Object.keys(entry).filter((key) => dimensionKeys.includes(key));

    let matchedAny = false;
    if (sharedKeys.length > 0) {
      const partial = Object.fromEntries(sharedKeys.map((key) => [key, entry[key]]));
      for (const combo of result) {
        if (matches(combo, partial)) {
          Object.assign(combo, entry);
          matchedAny = true;
        }
      }
    }

    if (!matchedAny) {
      result.push({ ...entry });
    }
  }

  return result;
}

/**
 * Removes any row that matches every key/value pair of at least one exclude
 * entry.
 */
function applyExcludes(
  combinations: MatrixCombination[],
  excludes: MatrixCombination[],
): MatrixCombination[] {
  return combinations.filter((combo) => !excludes.some((entry) => matches(combo, entry)));
}

/**
 * Generates a build matrix from the given config.
 *
 * Throws a descriptive Error if `maxParallel` is invalid or if the generated
 * matrix exceeds either the caller-supplied `maxMatrixSize` or GitHub
 * Actions' own hard limit of 256 rows.
 */
export function generateMatrix(config: MatrixConfig): MatrixResult {
  if (config.maxParallel !== undefined && config.maxParallel < 1) {
    throw new Error(
      `Invalid max-parallel: ${config.maxParallel}. max-parallel must be an integer >= 1.`,
    );
  }

  let include = cartesianProduct(config.dimensions);

  if (config.exclude && config.exclude.length > 0) {
    include = applyExcludes(include, config.exclude);
  }

  if (config.include && config.include.length > 0) {
    include = applyIncludes(include, config.include);
  }

  const effectiveLimit = Math.min(
    GITHUB_ACTIONS_MAX_MATRIX_SIZE,
    config.maxMatrixSize ?? GITHUB_ACTIONS_MAX_MATRIX_SIZE,
  );

  if (include.length > effectiveLimit) {
    throw new Error(
      `Generated matrix has ${include.length} combinations, which exceeds maximum matrix size of ${effectiveLimit} ` +
        `(GitHub Actions' hard limit is ${GITHUB_ACTIONS_MAX_MATRIX_SIZE}).`,
    );
  }

  const matrix: StrategyMatrix = {
    include,
    "fail-fast": config.failFast ?? true,
  };

  if (config.maxParallel !== undefined) {
    matrix["max-parallel"] = config.maxParallel;
  }

  return { matrix };
}
