// Environment build matrix generator for GitHub Actions `strategy.matrix`.
//
// Given a config describing OS options, language versions, and feature
// flags, this module expands the cartesian product of those axes, applies
// include/exclude rules following GitHub's documented matrix semantics,
// enforces a maximum matrix size, and emits the full matrix as JSON that is
// ready to drop into a workflow's `strategy:` block.

/** A single value an axis or a combination entry can take. */
export type AxisValue = string | number | boolean;

/** A fully-resolved job combination: axis name -> value. */
export type Combination = Record<string, AxisValue>;

/** Named axes (os, version, flags...), each a list of allowed values. */
export type Axes = Record<string, AxisValue[]>;

/**
 * Compute the cartesian product of every axis, in row-major order (the axis
 * declared first varies slowest). An empty axis makes the whole product
 * empty; zero axes yields a single empty combination.
 */
export function cartesianProduct(axes: Axes): Combination[] {
  let combos: Combination[] = [{}];
  for (const [key, values] of Object.entries(axes)) {
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

/** True when `combo` contains every key/value pair present in `rule`. */
function matchesRule(combo: Combination, rule: Combination): boolean {
  return Object.entries(rule).every(([key, value]) => combo[key] === value);
}

/**
 * Remove any combination that matches every key/value pair of at least one
 * exclude rule. A rule may specify only a subset of keys (e.g. `{ os: "x" }`
 * drops every combination with that OS regardless of other axes). A rule
 * that references a key the matrix doesn't have can never match, so it is
 * silently a no-op rather than an error.
 */
export function applyExclude(combos: Combination[], excludeRules: Combination[]): Combination[] {
  if (excludeRules.length === 0) return combos;
  return combos.filter((combo) => !excludeRules.some((rule) => matchesRule(combo, rule)));
}

/**
 * Apply GitHub Actions `include` semantics on top of the cross-product
 * combinations.
 *
 * For each include rule, in order:
 *  - It is compatible with an original-axis combination unless it tries to
 *    change one of that combination's ORIGINAL axis values to something
 *    else (a value the rule added earlier CAN be overwritten by a later
 *    rule; a value that came from the initial `os`/`version`/flags axes
 *    cannot).
 *  - If it is compatible with at least one original combination, its extra
 *    fields are merged into every compatible one.
 *  - Otherwise, it becomes a brand-new standalone combination.
 *
 * Standalone combinations created this way are never reconsidered as merge
 * targets for a later include rule — this matches GitHub's own documented
 * example, where two non-matching `include` rules that share a key produce
 * two separate rows rather than merging into each other.
 */
export function applyInclude(
  combos: Combination[],
  includeRules: Combination[],
  originalKeys: Set<string>,
): Combination[] {
  // Mutable copies of the original cross-product rows; these accumulate
  // fields from every compatible include rule as we go.
  const base = combos.map((combo) => ({ ...combo }));
  const standalone: Combination[] = [];

  for (const rule of includeRules) {
    const targets = base.filter(
      (combo) =>
        !Object.entries(rule).some(
          ([key, value]) => originalKeys.has(key) && combo[key] !== value,
        ),
    );
    if (targets.length > 0) {
      for (const combo of targets) Object.assign(combo, rule);
    } else {
      standalone.push({ ...rule });
    }
  }

  return [...base, ...standalone];
}

/** Reserved axis names that come from the top-level config, not `flags`. */
const RESERVED_AXIS_NAMES = new Set(["os", "version"]);

/** GitHub Actions itself refuses to run a matrix with more than 256 jobs. */
export const DEFAULT_MAX_MATRIX_SIZE = 256;

/**
 * Config describing the matrix to generate, typically parsed from a JSON
 * fixture file. `os` and `version` are required axes; `flags` holds any
 * number of additional feature-flag axes (e.g. `{ coverage: [true, false] }`).
 */
export interface MatrixGeneratorConfig {
  os: AxisValue[];
  version: AxisValue[];
  flags?: Record<string, AxisValue[]>;
  include?: Combination[];
  exclude?: Combination[];
  /** Cancel remaining jobs on first failure. Defaults to true, GitHub's own default. */
  failFast?: boolean;
  /** Maximum number of jobs run concurrently. Omitted entirely when not set. */
  maxParallel?: number;
  /** Hard cap on the number of generated combinations. Defaults to 256. */
  maxMatrixSize?: number;
}

/** Thrown when the config itself is structurally invalid. */
export class MatrixConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MatrixConfigError";
  }
}

/** Thrown when the generated matrix exceeds `maxMatrixSize`. */
export class MatrixSizeExceededError extends Error {
  constructor(
    public readonly size: number,
    public readonly maxMatrixSize: number,
  ) {
    super(
      `Generated matrix has ${size} combinations, exceeding the maximum allowed size of ${maxMatrixSize}.`,
    );
    this.name = "MatrixSizeExceededError";
  }
}

/** The generated matrix, shaped to drop directly into a `strategy:` block. */
export interface GeneratedMatrix {
  matrix: { include: Combination[] };
  "fail-fast": boolean;
  "max-parallel"?: number;
  matrixSize: number;
}

function isNonEmptyArray(value: unknown): value is AxisValue[] {
  return Array.isArray(value) && value.length > 0;
}

/** Validate the config and merge os/version/flags into one set of axes. */
function buildAxes(config: MatrixGeneratorConfig): Axes {
  if (!isNonEmptyArray(config.os)) {
    throw new MatrixConfigError("`os` must be a non-empty array of OS values");
  }
  if (!isNonEmptyArray(config.version)) {
    throw new MatrixConfigError("`version` must be a non-empty array of language versions");
  }

  const axes: Axes = { os: config.os, version: config.version };
  for (const [name, values] of Object.entries(config.flags ?? {})) {
    if (RESERVED_AXIS_NAMES.has(name)) {
      throw new MatrixConfigError(
        `\`flags.${name}\` collides with the reserved axis name "${name}"; rename the flag`,
      );
    }
    if (!isNonEmptyArray(values)) {
      throw new MatrixConfigError(`\`flags.${name}\` must be a non-empty array of values`);
    }
    axes[name] = values;
  }
  return axes;
}

/**
 * Generate a complete GitHub Actions build matrix from a config describing
 * OS options, language versions, and feature flags. Applies exclude rules,
 * then include rules (GitHub's own processing order), and validates the
 * result against `maxMatrixSize` before returning.
 */
export function generateMatrix(config: MatrixGeneratorConfig): GeneratedMatrix {
  const axes = buildAxes(config);
  const originalKeys = new Set(Object.keys(axes));

  let combos = cartesianProduct(axes);
  combos = applyExclude(combos, config.exclude ?? []);
  combos = applyInclude(combos, config.include ?? [], originalKeys);

  const maxMatrixSize = config.maxMatrixSize ?? DEFAULT_MAX_MATRIX_SIZE;
  if (combos.length > maxMatrixSize) {
    throw new MatrixSizeExceededError(combos.length, maxMatrixSize);
  }

  const result: GeneratedMatrix = {
    matrix: { include: combos },
    "fail-fast": config.failFast ?? true,
    matrixSize: combos.length,
  };
  if (config.maxParallel !== undefined) {
    result["max-parallel"] = config.maxParallel;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Command-line interface.
//
// Usage:
//   bun run matrix-generator.ts <config.json>   # read config from a file
//   bun run matrix-generator.ts -               # read config JSON from stdin
//
// Prints the generated matrix as pretty JSON on stdout and exits 0. On any
// error (bad usage, unreadable file, invalid JSON, invalid config, or an
// oversized matrix) it prints a meaningful message to stderr and exits 1.
// ---------------------------------------------------------------------------

const USAGE =
  "Usage: bun run matrix-generator.ts <config.json | ->\n" +
  "  Reads a JSON matrix config (os, version, flags, include, exclude,\n" +
  "  failFast, maxParallel, maxMatrixSize) and prints the generated\n" +
  "  GitHub Actions build matrix as JSON.";

export async function main(argv: string[]): Promise<number> {
  const arg = argv[0];
  if (!arg) {
    process.stderr.write(USAGE + "\n");
    return 1;
  }

  let raw: string;
  try {
    raw = arg === "-" ? await Bun.stdin.text() : await Bun.file(arg).text();
  } catch (err) {
    process.stderr.write(`Failed to read config from "${arg}": ${(err as Error).message}\n`);
    return 1;
  }

  let config: MatrixGeneratorConfig;
  try {
    config = JSON.parse(raw) as MatrixGeneratorConfig;
  } catch (err) {
    process.stderr.write(`Invalid JSON in config "${arg}": ${(err as Error).message}\n`);
    return 1;
  }

  try {
    const matrix = generateMatrix(config);
    process.stdout.write(JSON.stringify(matrix, null, 2) + "\n");
    return 0;
  } catch (err) {
    process.stderr.write(`Error: ${(err as Error).message}\n`);
    return 1;
  }
}

// Only run the CLI when this file is executed directly, not when imported.
if (import.meta.main) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
