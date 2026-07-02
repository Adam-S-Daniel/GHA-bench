/**
 * Environment matrix generator for GitHub Actions strategy.matrix.
 *
 * Takes a configuration of OS options, language versions and feature flags,
 * expands the cartesian product, applies exclude/include rules (following
 * GitHub Actions semantics), validates the final size, and produces a
 * complete `strategy` object ready to embed in a workflow.
 */

/** A single matrix combination, e.g. { os: "ubuntu-latest", "language-version": "20" }. */
export type Combination = Record<string, string>;

/** Input configuration describing the environments to build. */
export interface MatrixConfig {
  /** Operating systems (runner labels), e.g. ["ubuntu-latest", "macos-latest"]. */
  os: string[];
  /** Language/runtime versions, e.g. ["18", "20"]. Emitted as `language-version`. */
  languageVersions: string[];
  /** Optional feature flags; each becomes a value of the `feature` dimension. */
  featureFlags?: string[];
}

/** Matrix dimension names used in the generated combinations. */
const DIMENSION_KEYS = {
  os: "os",
  languageVersions: "language-version",
  featureFlags: "feature",
} as const;

/**
 * Expand the configured dimensions into the full cartesian product.
 * Dimension order (os -> language-version -> feature) is deterministic so
 * output is stable and easy to assert on.
 */
export function expandCombinations(config: MatrixConfig): Combination[] {
  // Build an ordered list of [key, values] pairs, skipping absent dimensions.
  const dimensions: Array<[string, string[]]> = [];
  dimensions.push([DIMENSION_KEYS.os, config.os]);
  dimensions.push([DIMENSION_KEYS.languageVersions, config.languageVersions]);
  if (config.featureFlags && config.featureFlags.length > 0) {
    dimensions.push([DIMENSION_KEYS.featureFlags, config.featureFlags]);
  }

  // Classic iterative cartesian product: start with one empty combination
  // and multiply it by each dimension in turn.
  let combos: Combination[] = [{}];
  for (const [key, values] of dimensions) {
    const next: Combination[] = [];
    for (const combo of combos) {
      for (const value of values) {
        next.push({ ...combo, [key]: value });
      }
    }
    combos = next;
  }
  return combos;
}

/**
 * A rule used by include/exclude: a partial combination. For excludes,
 * a combination is removed when EVERY key in the rule matches it
 * (keys not listed in the rule match anything) — GitHub Actions semantics.
 */
export type MatrixRule = Record<string, string>;

/** True when every key/value in `rule` is present and equal in `combo`. */
function ruleMatches(combo: Combination, rule: MatrixRule): boolean {
  return Object.entries(rule).every(([key, value]) => combo[key] === value);
}

/** Remove every combination matched by any exclude rule. */
export function applyExcludes(
  combos: Combination[],
  excludes: MatrixRule[],
): Combination[] {
  return combos.filter((combo) => !excludes.some((rule) => ruleMatches(combo, rule)));
}

/**
 * Apply include rules following GitHub Actions semantics:
 *
 * - Keys of an include entry are split into "original matrix keys"
 *   (dimensions of the expanded matrix) and "extra keys".
 * - If at least one existing combination matches ALL of the entry's original
 *   matrix keys, the entry's extra keys are merged into every matching
 *   combination (original values are never overwritten).
 * - If no combination matches, the entry is appended as a brand-new
 *   standalone combination.
 * - An entry with only extra keys matches (and is merged into) everything.
 */
export function applyIncludes(
  combos: Combination[],
  includes: MatrixRule[],
  originalKeys: string[],
): Combination[] {
  const result = combos.map((combo) => ({ ...combo }));
  const keySet = new Set(originalKeys);

  for (const entry of includes) {
    // Only the entry's original-dimension keys participate in matching.
    const matchRule: MatrixRule = {};
    const extras: MatrixRule = {};
    for (const [key, value] of Object.entries(entry)) {
      if (keySet.has(key)) {
        matchRule[key] = value;
      } else {
        extras[key] = value;
      }
    }

    const matches = result.filter((combo) => ruleMatches(combo, matchRule));
    if (matches.length > 0) {
      for (const combo of matches) {
        Object.assign(combo, extras);
      }
    } else {
      // No existing combination can absorb this entry without overwriting
      // original values -> it becomes a new combination.
      result.push({ ...entry });
    }
  }
  return result;
}

/** Full generator options: dimensions plus strategy-level settings. */
export interface GeneratorConfig extends MatrixConfig {
  /** Combinations (partial) to remove from the expanded matrix. */
  exclude?: MatrixRule[];
  /** Combinations to extend or add, GitHub Actions include semantics. */
  include?: MatrixRule[];
  /** strategy.max-parallel — omit to let GitHub use all available runners. */
  maxParallel?: number;
  /** strategy.fail-fast — defaults to true, matching GitHub Actions. */
  failFast?: boolean;
  /** Maximum number of jobs allowed; defaults to GitHub's 256-job limit. */
  maxSize?: number;
}

/** The generated `strategy` block, ready for a GitHub Actions workflow. */
export interface Strategy {
  "fail-fast": boolean;
  "max-parallel"?: number;
  /** Fully-expanded combinations, expressed via matrix.include. */
  matrix: { include: Combination[] };
}

export interface GenerateResult {
  strategy: Strategy;
  /** Number of jobs the matrix will spawn. */
  jobCount: number;
}

/**
 * Generate the complete strategy.matrix from a configuration:
 * expand -> exclude -> include, then wrap with fail-fast / max-parallel.
 * The result uses the `matrix.include` form (a list of explicit
 * combinations), which GitHub Actions accepts as a full matrix definition.
 */
export function generateMatrix(config: GeneratorConfig): GenerateResult {
  const expanded = expandCombinations(config);
  const originalKeys = expanded.length > 0 ? Object.keys(expanded[0]!) : [];

  const afterExcludes = applyExcludes(expanded, config.exclude ?? []);
  const combos = applyIncludes(afterExcludes, config.include ?? [], originalKeys);

  // Guard against oversized matrices (GitHub refuses runs above 256 jobs).
  const maxSize = config.maxSize ?? GITHUB_MATRIX_LIMIT;
  if (combos.length > maxSize) {
    throw new MatrixValidationError(
      `Matrix size ${combos.length} exceeds the maximum allowed size ${maxSize}. ` +
        "Reduce dimensions or add exclude rules.",
    );
  }

  const strategy: Strategy = {
    // GitHub defaults fail-fast to true; mirror that here.
    "fail-fast": config.failFast ?? true,
    matrix: { include: combos },
  };
  if (config.maxParallel !== undefined) {
    // Keep key order stable: rebuild with max-parallel between the others.
    return {
      strategy: {
        "fail-fast": strategy["fail-fast"],
        "max-parallel": config.maxParallel,
        matrix: strategy.matrix,
      },
      jobCount: combos.length,
    };
  }
  return { strategy, jobCount: combos.length };
}

/** Error thrown for any invalid configuration or oversized matrix. */
export class MatrixValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixValidationError";
  }
}

/** GitHub Actions caps a job matrix at 256 jobs per workflow run. */
export const GITHUB_MATRIX_LIMIT = 256;

/** Narrowing helper: non-null plain object. */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Coerce a config array of strings/numbers to strings, rejecting anything
 * else with a message that names the offending field.
 */
function toStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new MatrixValidationError(
      `Config error: "${field}" must be a non-empty array of strings`,
    );
  }
  return value.map((item, i) => {
    if (typeof item === "string") return item;
    if (typeof item === "number" && Number.isFinite(item)) return String(item);
    throw new MatrixValidationError(
      `Config error: "${field}[${i}]" must be a string or number, got ${typeof item}`,
    );
  });
}

/** Validate an array of include/exclude rules, coercing values to strings. */
function toRuleArray(value: unknown, field: string): MatrixRule[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new MatrixValidationError(`Config error: "${field}" must be an array of objects`);
  }
  return value.map((entry, i) => {
    if (!isPlainObject(entry)) {
      throw new MatrixValidationError(`Config error: "${field}[${i}]" must be an object`);
    }
    const rule: MatrixRule = {};
    for (const [key, raw] of Object.entries(entry)) {
      if (typeof raw === "string") rule[key] = raw;
      else if (typeof raw === "number" && Number.isFinite(raw)) rule[key] = String(raw);
      else if (typeof raw === "boolean") rule[key] = String(raw);
      else {
        throw new MatrixValidationError(
          `Config error: "${field}[${i}].${key}" must be a string, number or boolean`,
        );
      }
    }
    return rule;
  });
}

/**
 * Validate raw JSON input (e.g. a parsed config file) and normalize it into
 * a typed GeneratorConfig. Throws MatrixValidationError with a message that
 * pinpoints the invalid field.
 */
export function validateConfig(raw: unknown): GeneratorConfig {
  if (!isPlainObject(raw)) {
    throw new MatrixValidationError("Config error: input must be a JSON object");
  }

  const config: GeneratorConfig = {
    os: toStringArray(raw.os, "os"),
    languageVersions: toStringArray(raw.languageVersions, "languageVersions"),
  };

  if (raw.featureFlags !== undefined) {
    config.featureFlags = toStringArray(raw.featureFlags, "featureFlags");
  }
  config.exclude = toRuleArray(raw.exclude, "exclude");
  config.include = toRuleArray(raw.include, "include");

  if (raw.maxParallel !== undefined) {
    if (
      typeof raw.maxParallel !== "number" ||
      !Number.isInteger(raw.maxParallel) ||
      raw.maxParallel < 1
    ) {
      throw new MatrixValidationError(
        'Config error: "maxParallel" must be a positive integer',
      );
    }
    config.maxParallel = raw.maxParallel;
  }
  if (raw.failFast !== undefined) {
    if (typeof raw.failFast !== "boolean") {
      throw new MatrixValidationError('Config error: "failFast" must be a boolean');
    }
    config.failFast = raw.failFast;
  }
  if (raw.maxSize !== undefined) {
    if (typeof raw.maxSize !== "number" || !Number.isInteger(raw.maxSize) || raw.maxSize < 1) {
      throw new MatrixValidationError('Config error: "maxSize" must be a positive integer');
    }
    config.maxSize = raw.maxSize;
  }
  return config;
}
