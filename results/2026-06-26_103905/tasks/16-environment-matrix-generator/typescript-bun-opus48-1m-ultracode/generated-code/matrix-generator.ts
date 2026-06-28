/**
 * Environment Matrix Generator
 * ============================
 *
 * Given a configuration describing OS options, language versions, and feature
 * flags, this module produces a build matrix (as JSON) suitable for a GitHub
 * Actions `strategy.matrix`. It faithfully implements GitHub's documented
 * matrix-expansion semantics:
 *
 *   1. Take the cartesian product of every matrix dimension.
 *   2. Remove any combination matched (partially) by an `exclude` entry.
 *   3. Fold in each `include` entry: merge it into existing combinations where
 *      it does not overwrite an original matrix value, otherwise append it as a
 *      brand-new combination.
 *
 * On top of that it threads through `max-parallel` and `fail-fast`, and
 * validates that the resulting matrix does not exceed a configurable maximum
 * size (GitHub's own hard limit is 256 jobs per matrix).
 *
 * The file is both a library (the pure functions below are unit-tested) and a
 * CLI (`bun run matrix-generator.ts <config.json>`), guarded by
 * `import.meta.main` so importing it for tests has no side effects.
 */

/** A scalar matrix value. GitHub allows richer values, but OS/version/flag
 *  axes are scalars; objects are still handled via structural equality. */
export type MatrixValue = string | number | boolean | null | MatrixValueObject;
export interface MatrixValueObject {
  [key: string]: MatrixValue;
}

/** A single concrete job configuration, e.g. `{ os: "ubuntu-latest", node: "20" }`. */
export type Combination = Record<string, MatrixValue>;

/**
 * Structural equality for matrix values. Scalars compare with `===`; objects
 * compare by their (key-sorted) JSON shape so that exclude/include matching is
 * robust even when a value is an object rather than a plain scalar.
 */
export function valuesEqual(a: MatrixValue, b: MatrixValue): boolean {
  if (a === b) return true;
  if (a === null || b === null) return false;
  if (typeof a !== "object" || typeof b !== "object") return false;
  return stableStringify(a) === stableStringify(b);
}

/** Deterministic JSON with object keys sorted, used for structural comparison. */
function stableStringify(value: MatrixValue): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  const sortedKeys = Object.keys(value).sort();
  const parts = sortedKeys.map(
    (k) => `${JSON.stringify(k)}:${stableStringify(value[k] as MatrixValue)}`,
  );
  return `{${parts.join(",")}}`;
}

/**
 * Does `combination` satisfy every key/value pair in `pattern`?
 *
 * This is a *partial* match: keys absent from `pattern` are ignored, so a
 * pattern of `{ os: "windows-latest" }` matches any windows row regardless of
 * the other axes. A key present in `pattern` but absent from `combination`
 * never matches.
 */
export function matchesPattern(combination: Combination, pattern: Combination): boolean {
  return Object.entries(pattern).every(
    ([key, value]) => key in combination && valuesEqual(combination[key] as MatrixValue, value),
  );
}

/**
 * Remove every combination that is (partially) matched by any exclude rule.
 * Mirrors GitHub's rule that "an excluded configuration only needs to be a
 * partial match for it to be excluded".
 */
export function applyExclude(
  combinations: Combination[],
  excludes: Combination[],
): Combination[] {
  if (excludes.length === 0) return combinations;
  return combinations.filter(
    (combo) => !excludes.some((rule) => matchesPattern(combo, rule)),
  );
}

/**
 * Fold `include` entries into the (post-exclude) combinations, following
 * GitHub's exact algorithm:
 *
 *   For each object in the include list, its key:value pairs are added to each
 *   matrix combination *if none of the pairs overwrite an original matrix
 *   value*. If the object cannot be added to ANY combination, a new combination
 *   is created instead. Original matrix values are never overwritten, but
 *   previously-added (include-sourced) values may be.
 *
 * A key "overwrites an original matrix value" when it is one of the original
 * `dimensionKeys` and its value differs from the combination's value for that
 * key. Newly created combinations are not themselves merge targets for later
 * include entries — only the original combinations are.
 *
 * The input array and its objects are not mutated; a fresh result is returned.
 */
export function applyInclude(
  combinations: Combination[],
  includes: Combination[],
  dimensionKeys: string[],
): Combination[] {
  const merged: Combination[] = combinations.map((combo) => ({ ...combo }));
  const appended: Combination[] = [];
  const dimensionKeySet = new Set(dimensionKeys);

  for (const include of includes) {
    let mergedSomewhere = false;
    for (const combo of merged) {
      const overwritesDimension = Object.entries(include).some(
        ([key, value]) =>
          dimensionKeySet.has(key) && !valuesEqual(combo[key] as MatrixValue, value),
      );
      if (overwritesDimension) continue;

      mergedSomewhere = true;
      for (const [key, value] of Object.entries(include)) {
        combo[key] = value;
      }
    }
    if (!mergedSomewhere) appended.push({ ...include });
  }

  return [...merged, ...appended];
}

/* -------------------------------------------------------------------------- */
/* Configuration, errors, and the top-level generator                          */
/* -------------------------------------------------------------------------- */

/** GitHub's hard cap on the number of jobs a single matrix may generate. */
export const GITHUB_MAX_MATRIX_SIZE = 256;

/** Keys inside `matrix` that are reserved by GitHub and are not dimensions. */
const RESERVED_MATRIX_KEYS = new Set(["include", "exclude"]);

/** Thrown when the supplied configuration is structurally invalid. */
export class MatrixConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixConfigError";
  }
}

/** Thrown (only in strict mode) when the generated matrix exceeds max-size. */
export class MatrixSizeError extends Error {
  readonly size: number;
  readonly maxSize: number;
  constructor(size: number, maxSize: number) {
    super(
      `Generated matrix has ${size} combinations, which exceeds the maximum of ${maxSize}. ` +
        `Reduce the number of dimension values or raise max-size (GitHub allows up to ${GITHUB_MAX_MATRIX_SIZE}).`,
    );
    this.name = "MatrixSizeError";
    this.size = size;
    this.maxSize = maxSize;
  }
}

/** Options controlling generation behaviour. */
export interface GenerateOptions {
  /** When true, exceeding max-size throws `MatrixSizeError` instead of being
   *  reported via the `within-limit` flag. */
  strict?: boolean;
}

/** The generated, ready-to-serialise result. */
export interface MatrixResult {
  strategy: {
    "fail-fast": boolean;
    "max-parallel"?: number;
    matrix: { include: Combination[] };
  };
  size: number;
  "max-size": number;
  "within-limit": boolean;
}

/** A plain (non-array, non-null) object — used to narrow `unknown` input. */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Read a boolean field, accepting kebab- and camelCase keys, with a default. */
function readBoolean(
  source: Record<string, unknown>,
  keys: string[],
  fallback: boolean,
): boolean {
  for (const key of keys) {
    if (key in source) {
      const value = source[key];
      if (typeof value !== "boolean") {
        throw new MatrixConfigError(`"${key}" must be a boolean, got ${describe(value)}.`);
      }
      return value;
    }
  }
  return fallback;
}

/** Read an optional positive-integer field, accepting kebab/camelCase keys. */
function readPositiveInt(
  source: Record<string, unknown>,
  keys: string[],
): number | undefined {
  for (const key of keys) {
    if (key in source) {
      const value = source[key];
      if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
        throw new MatrixConfigError(
          `"${key}" must be a positive integer, got ${describe(value)}.`,
        );
      }
      return value;
    }
  }
  return undefined;
}

/** Short human-readable description of an unexpected value, for error messages. */
function describe(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "an array";
  return `${typeof value} (${JSON.stringify(value)})`;
}

/** Validate that a value is an array of plain objects (for include/exclude). */
function readCombinationList(
  source: Record<string, unknown>,
  key: string,
): Combination[] {
  if (!(key in source)) return [];
  const value = source[key];
  if (!Array.isArray(value)) {
    throw new MatrixConfigError(`"matrix.${key}" must be an array, got ${describe(value)}.`);
  }
  return value.map((entry, index) => {
    if (!isPlainObject(entry)) {
      throw new MatrixConfigError(
        `"matrix.${key}[${index}]" must be an object, got ${describe(entry)}.`,
      );
    }
    return entry as Combination;
  });
}

/**
 * Generate a complete GitHub Actions strategy matrix from a configuration.
 *
 * Pipeline: cartesian product of dimensions -> apply exclude -> apply include
 * -> validate size. The expanded combinations are emitted as an "include only"
 * matrix (`strategy.matrix.include`), which GitHub runs verbatim with no
 * further expansion — making the output unambiguous and directly usable.
 */
export function generateMatrix(
  config: unknown,
  options: GenerateOptions = {},
): MatrixResult {
  if (!isPlainObject(config)) {
    throw new MatrixConfigError(
      `Configuration must be a JSON object, got ${describe(config)}.`,
    );
  }

  const failFast = readBoolean(config, ["fail-fast", "failFast"], true);
  const maxParallel = readPositiveInt(config, ["max-parallel", "maxParallel"]);
  const maxSize = readPositiveInt(config, ["max-size", "maxSize"]) ?? GITHUB_MAX_MATRIX_SIZE;

  const matrix = config.matrix;
  if (!isPlainObject(matrix)) {
    throw new MatrixConfigError(
      `Configuration must contain a "matrix" object, got ${describe(matrix)}.`,
    );
  }

  // Every non-reserved key in `matrix` is a dimension; values must be a
  // non-empty array. Declaration order is preserved so output is deterministic.
  const dimensions: Dimension[] = [];
  for (const [key, value] of Object.entries(matrix)) {
    if (RESERVED_MATRIX_KEYS.has(key)) continue;
    if (!Array.isArray(value) || value.length === 0) {
      throw new MatrixConfigError(
        `Dimension "${key}" must be a non-empty array of values, got ${describe(value)}.`,
      );
    }
    dimensions.push([key, value as MatrixValue[]]);
  }

  const includes = readCombinationList(matrix, "include");
  const excludes = readCombinationList(matrix, "exclude");

  if (dimensions.length === 0 && includes.length === 0) {
    throw new MatrixConfigError(
      'The "matrix" must define at least one dimension or one include entry.',
    );
  }

  const dimensionKeys = dimensions.map(([name]) => name);
  const product = cartesianProduct(dimensions);
  const afterExclude = applyExclude(product, excludes);
  const combinations = applyInclude(afterExclude, includes, dimensionKeys);

  if (combinations.length === 0) {
    throw new MatrixConfigError(
      "Matrix expansion produced zero combinations (every combination was excluded). " +
        "Relax the exclude rules or add include entries.",
    );
  }

  const size = combinations.length;
  const withinLimit = size <= maxSize;
  if (!withinLimit && options.strict) {
    throw new MatrixSizeError(size, maxSize);
  }

  const strategy: MatrixResult["strategy"] = {
    "fail-fast": failFast,
    matrix: { include: combinations },
  };
  if (maxParallel !== undefined) {
    strategy["max-parallel"] = maxParallel;
  }

  return {
    strategy,
    size,
    "max-size": maxSize,
    "within-limit": withinLimit,
  };
}

/* -------------------------------------------------------------------------- */
/* CLI                                                                          */
/* -------------------------------------------------------------------------- */

const USAGE = `Environment Matrix Generator

Generate a GitHub Actions strategy.matrix (JSON) from a configuration of OS
options, language versions, and feature flags, applying include/exclude rules,
max-parallel/fail-fast settings, and a max-size validation check.

Usage:
  bun run matrix-generator.ts <config.json> [options]
  cat config.json | bun run matrix-generator.ts - [options]

Options:
  --strict     Exit with code 2 if the matrix exceeds max-size (default: report
               the overflow via the "within-limit" flag and still exit 0).
  --compact    Emit single-line JSON instead of pretty-printed (2-space) JSON.
  -h, --help   Show this help.

Exit codes:
  0  success
  1  invalid configuration / I/O / JSON error
  2  matrix exceeds max-size (only when --strict is set)
`;

/** Read the raw config text from a file path, or from stdin when "-"/omitted. */
async function readConfigSource(
  path: string | undefined,
): Promise<{ text: string; label: string }> {
  if (path === undefined || path === "-") {
    return { text: await Bun.stdin.text(), label: "<stdin>" };
  }
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new MatrixConfigError(`Config file not found: ${path}`);
  }
  return { text: await file.text(), label: path };
}

/**
 * CLI entry point. Returns a process exit code rather than calling
 * `process.exit` directly, so it can be unit-tested if desired. All errors are
 * reported on stderr with an "Error:" prefix and a meaningful message.
 */
export async function runCli(argv: string[]): Promise<number> {
  const positionals: string[] = [];
  let strict = false;
  let compact = false;

  for (const arg of argv) {
    if (arg === "--strict") {
      strict = true;
    } else if (arg === "--compact") {
      compact = true;
    } else if (arg === "-h" || arg === "--help") {
      process.stdout.write(USAGE);
      return 0;
    } else if (arg !== "-" && arg.startsWith("--")) {
      process.stderr.write(`Error: unknown option "${arg}".\n\n${USAGE}`);
      return 1;
    } else {
      positionals.push(arg);
    }
  }

  // Read + parse the configuration.
  let source: { text: string; label: string };
  try {
    source = await readConfigSource(positionals[0]);
  } catch (error) {
    process.stderr.write(`Error: ${(error as Error).message}\n`);
    return 1;
  }

  let config: unknown;
  try {
    config = JSON.parse(source.text);
  } catch (error) {
    process.stderr.write(
      `Error: failed to parse JSON from ${source.label}: ${(error as Error).message}\n`,
    );
    return 1;
  }

  // Generate and emit.
  try {
    const result = generateMatrix(config, { strict });
    const json = compact ? JSON.stringify(result) : JSON.stringify(result, null, 2);
    process.stdout.write(`${json}\n`);
    return 0;
  } catch (error) {
    process.stderr.write(`Error: ${(error as Error).message}\n`);
    return error instanceof MatrixSizeError ? 2 : 1;
  }
}

// Only run as a CLI when executed directly (not when imported by tests).
if (import.meta.main) {
  process.exit(await runCli(Bun.argv.slice(2)));
}

/** A `[name, values]` pair describing one matrix dimension/axis. */
export type Dimension = [name: string, values: MatrixValue[]];

/**
 * Compute the cartesian product of the given dimensions.
 *
 * The FIRST dimension varies slowest and the LAST varies fastest, matching the
 * natural reading order of a GitHub Actions matrix block. With no dimensions we
 * return an empty list (not a single empty combination) so that an "include
 * only" matrix yields one job per include entry rather than collapsing them.
 */
export function cartesianProduct(dimensions: Dimension[]): Combination[] {
  if (dimensions.length === 0) return [];

  let combinations: Combination[] = [{}];
  for (const [name, values] of dimensions) {
    const next: Combination[] = [];
    for (const combo of combinations) {
      for (const value of values) {
        next.push({ ...combo, [name]: value });
      }
    }
    combinations = next;
  }
  return combinations;
}
