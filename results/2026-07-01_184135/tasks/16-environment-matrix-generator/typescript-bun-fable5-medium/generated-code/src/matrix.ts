/**
 * Environment matrix generator for GitHub Actions strategy.matrix.
 *
 * Approach:
 *  1. Validate the config (dimensions, max-parallel, max-size).
 *  2. Expand the cartesian product of os x versions x features into
 *     concrete combinations (os / version / feature keys).
 *  3. Apply exclude rules (GHA semantics: an exclude entry removes every
 *     combination whose values match ALL keys of the entry).
 *  4. Apply include rules (GHA semantics, simplified: an include whose
 *     matrix-dimension keys all match existing combinations extends those
 *     combinations with its extra keys; one that matches nothing is
 *     appended as a brand-new combination).
 *  5. Validate the final size against max-size (default: 256, the GitHub
 *     Actions hard limit on jobs per matrix).
 *  6. Emit both a GHA-native `strategy` block and the fully expanded
 *     `combinations` list, so callers can either hand the strategy to a
 *     workflow or consume the expanded jobs directly.
 */

/** One concrete matrix job. Standard keys plus any extras from `include`. */
export interface MatrixCombination {
  os: string;
  version: string;
  feature: string;
  [extra: string]: string;
}

/** A partial match used by exclude rules / include extension. */
export type MatrixSelector = Partial<Record<string, string>>;

/** Input configuration describing the environment matrix. */
export interface MatrixConfig {
  /** Operating system options, e.g. ["ubuntu-latest", "macos-latest"]. */
  os: string[];
  /** Language versions, e.g. ["18", "20"]. */
  versions: string[];
  /** Feature flags, e.g. ["stable", "experimental"]. */
  features: string[];
  /** Combinations to add or extend (applied after exclude). */
  include?: MatrixSelector[];
  /** Partial combinations to remove. */
  exclude?: MatrixSelector[];
  /** strategy.fail-fast (default true, matching GitHub Actions). */
  "fail-fast"?: boolean;
  /** strategy.max-parallel (omitted from output when not set). */
  "max-parallel"?: number;
  /** Maximum allowed combination count (default 256, the GHA limit). */
  "max-size"?: number;
}

/** The GHA-native strategy block emitted in the result. */
export interface Strategy {
  "fail-fast": boolean;
  "max-parallel"?: number;
  matrix: {
    os: string[];
    version: string[];
    feature: string[];
    include?: MatrixSelector[];
    exclude?: MatrixSelector[];
  };
}

export interface MatrixResult {
  strategy: Strategy;
  combinations: MatrixCombination[];
  count: number;
}

/** All validation/generation failures raise this typed error. */
export class MatrixError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixError";
  }
}

/** GitHub Actions caps a matrix at 256 jobs per workflow run. */
const GHA_MAX_MATRIX_SIZE = 256;

/** The three configured dimensions and the combination key each maps to. */
const DIMENSIONS: ReadonlyArray<{ configKey: keyof MatrixConfig; comboKey: string }> = [
  { configKey: "os", comboKey: "os" },
  { configKey: "versions", comboKey: "version" },
  { configKey: "features", comboKey: "feature" },
];

function assertStringArray(value: unknown, name: string): asserts value is string[] {
  const ok =
    Array.isArray(value) &&
    value.length > 0 &&
    value.every((v) => typeof v === "string" && v.length > 0);
  if (!ok) {
    throw new MatrixError(`Dimension "${name}" must be a non-empty array of strings`);
  }
}

function validateConfig(config: MatrixConfig): void {
  if (config === null || typeof config !== "object") {
    throw new MatrixError("Config must be a JSON object");
  }
  for (const { configKey } of DIMENSIONS) {
    assertStringArray(config[configKey], configKey);
  }
  const maxParallel = config["max-parallel"];
  if (maxParallel !== undefined && (!Number.isInteger(maxParallel) || maxParallel < 1)) {
    throw new MatrixError(`"max-parallel" must be a positive integer, got ${maxParallel}`);
  }
  const maxSize = config["max-size"];
  if (maxSize !== undefined && (!Number.isInteger(maxSize) || maxSize < 1)) {
    throw new MatrixError(`"max-size" must be a positive integer, got ${maxSize}`);
  }
  for (const listKey of ["include", "exclude"] as const) {
    const list = config[listKey];
    if (list !== undefined && !Array.isArray(list)) {
      throw new MatrixError(`"${listKey}" must be an array of objects`);
    }
  }
}

/** Does `combo` match every key/value pair of `selector`? */
function matches(combo: MatrixCombination, selector: MatrixSelector): boolean {
  return Object.entries(selector).every(([k, v]) => combo[k] === v);
}

function applyExcludes(
  combos: MatrixCombination[],
  excludes: MatrixSelector[],
): MatrixCombination[] {
  return combos.filter((combo) => !excludes.some((ex) => matches(combo, ex)));
}

/**
 * Apply include rules after excludes, mirroring GitHub Actions:
 * for each include entry, split its keys into ones that name an original
 * matrix dimension vs. extras. If some combination matches all the
 * dimension keys present in the entry AND the entry doesn't contradict it,
 * the entry's extra keys are merged into every matching combination.
 * Otherwise the entry becomes a new standalone combination.
 */
function applyIncludes(
  combos: MatrixCombination[],
  includes: MatrixSelector[],
): MatrixCombination[] {
  const dimensionKeys = new Set(DIMENSIONS.map((d) => d.comboKey));
  let result = combos.map((c) => ({ ...c }));

  for (const entry of includes) {
    const dimPart: MatrixSelector = {};
    const extraPart: MatrixSelector = {};
    for (const [k, v] of Object.entries(entry)) {
      (dimensionKeys.has(k) ? dimPart : extraPart)[k] = v;
    }

    const targets = result.filter((c) => matches(c, dimPart));
    if (targets.length > 0) {
      // Extend matching combinations with the extra keys.
      for (const combo of targets) {
        Object.assign(combo, extraPart);
      }
    } else {
      // Nothing matched: the entry stands alone as a new combination.
      result = [...result, { ...(entry as MatrixCombination) }];
    }
  }
  return result;
}

/** Generate the full matrix, or throw MatrixError with a clear message. */
export function generateMatrix(config: MatrixConfig): MatrixResult {
  validateConfig(config);

  // Cartesian product of the three dimensions, in stable nested order.
  let combinations: MatrixCombination[] = [];
  for (const os of config.os) {
    for (const version of config.versions) {
      for (const feature of config.features) {
        combinations.push({ os, version, feature });
      }
    }
  }

  combinations = applyExcludes(combinations, config.exclude ?? []);
  combinations = applyIncludes(combinations, config.include ?? []);

  // Size is checked on the FINAL set so excludes can rescue an oversized base.
  const maxSize = config["max-size"] ?? GHA_MAX_MATRIX_SIZE;
  if (combinations.length > maxSize) {
    throw new MatrixError(
      `Matrix size ${combinations.length} exceeds maximum allowed size ${maxSize}`,
    );
  }

  const strategy: Strategy = {
    "fail-fast": config["fail-fast"] ?? true,
    ...(config["max-parallel"] !== undefined
      ? { "max-parallel": config["max-parallel"] }
      : {}),
    matrix: {
      os: config.os,
      version: config.versions,
      feature: config.features,
      ...(config.include?.length ? { include: config.include } : {}),
      ...(config.exclude?.length ? { exclude: config.exclude } : {}),
    },
  };

  return { strategy, combinations, count: combinations.length };
}
