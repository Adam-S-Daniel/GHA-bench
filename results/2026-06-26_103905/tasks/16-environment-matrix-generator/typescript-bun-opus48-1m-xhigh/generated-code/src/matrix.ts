// ---------------------------------------------------------------------------
// Core matrix logic — pure functions, no I/O. Kept side-effect free so the
// TDD unit tests can exercise every rule directly without touching the
// filesystem, env vars, or the CLI layer.
// ---------------------------------------------------------------------------
import type {
  Combination,
  GeneratedStrategy,
  MatrixAxes,
  MatrixConfig,
  MatrixValue,
} from "./types.ts";

/**
 * Expand a set of matrix axes into the full cartesian product of combinations.
 *
 * Order matters and is part of the contract: the FIRST declared axis varies
 * slowest and the LAST declared axis varies fastest, matching GitHub Actions.
 * We build the product iteratively, growing one axis at a time, so the result
 * order is deterministic regardless of axis count.
 *
 * The empty product (no axes) is a single empty combination `[{}]` — this is
 * the identity element, which lets a config that only supplies `include`
 * entries still have a base row to attach them to.
 */
export function cartesianProduct(axes: MatrixAxes): Combination[] {
  let combos: Combination[] = [{}];

  for (const [key, values] of Object.entries(axes)) {
    const next: Combination[] = [];
    for (const combo of combos) {
      for (const value of values) {
        // Spread the accumulated combo and append this axis's value so the
        // earlier axes stay "outer" (slower-varying) than this one.
        next.push({ ...combo, [key]: value });
      }
    }
    combos = next;
  }

  return combos;
}

/** A plain (non-null, non-array) object guard. */
function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === "object" && value !== null && !Array.isArray(value)
  );
}

/** Is `value` a scalar that may legally appear as a matrix value? */
function isScalar(value: unknown): value is MatrixValue {
  return (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  );
}

/** A positive integer (used for maxParallel). */
function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

/** A non-negative integer (used for maxSize). */
function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

/**
 * Validate one `include` / `exclude` entry: it must be an object whose values
 * are all scalars. `label` is "include" or "exclude" so the error names the
 * offending field, and `index` points the user at the bad array element.
 */
function parseCombinationEntry(
  entry: unknown,
  label: string,
  index: number,
): Combination {
  if (!isPlainObject(entry)) {
    throw new Error(`"${label}" entry at index ${index} must be an object`);
  }
  const result: Combination = {};
  for (const [key, value] of Object.entries(entry)) {
    if (!isScalar(value)) {
      throw new Error(
        `"${label}" entry at index ${index} has a non-scalar value for ` +
          `key "${key}" (only string, number, and boolean are allowed)`,
      );
    }
    result[key] = value;
  }
  return result;
}

/**
 * Parse and validate untrusted input (typically `JSON.parse` output) into a
 * well-formed `MatrixConfig`. Every failure throws an `Error` whose message
 * names the offending field and explains the expectation, so a misconfigured
 * CI pipeline fails with a clear diagnostic instead of a cryptic crash.
 */
export function parseConfig(raw: unknown): MatrixConfig {
  if (!isPlainObject(raw)) {
    throw new Error(
      "Configuration must be a JSON object with a \"matrix\" field",
    );
  }

  // --- matrix (required) ---------------------------------------------------
  if (!("matrix" in raw) || raw.matrix === undefined) {
    throw new Error('Configuration is missing the required "matrix" object');
  }
  if (!isPlainObject(raw.matrix)) {
    throw new Error('The "matrix" field must be an object mapping axes to value arrays');
  }
  const axisEntries = Object.entries(raw.matrix);
  if (axisEntries.length === 0) {
    throw new Error('The "matrix" object must declare at least one axis');
  }

  const matrix: MatrixAxes = {};
  for (const [axis, values] of axisEntries) {
    if (!Array.isArray(values) || values.length === 0) {
      throw new Error(`Matrix axis "${axis}" must be a non-empty array of values`);
    }
    for (const value of values) {
      if (!isScalar(value)) {
        throw new Error(
          `Matrix axis "${axis}" contains a non-scalar value ` +
            `(only string, number, and boolean are allowed)`,
        );
      }
    }
    matrix[axis] = values as MatrixValue[];
  }

  const config: MatrixConfig = { matrix };

  // --- include (optional) --------------------------------------------------
  if ("include" in raw && raw.include !== undefined) {
    if (!Array.isArray(raw.include)) {
      throw new Error('"include" must be an array of objects');
    }
    config.include = raw.include.map((entry, i) =>
      parseCombinationEntry(entry, "include", i),
    );
  }

  // --- exclude (optional) --------------------------------------------------
  if ("exclude" in raw && raw.exclude !== undefined) {
    if (!Array.isArray(raw.exclude)) {
      throw new Error('"exclude" must be an array of objects');
    }
    config.exclude = raw.exclude.map((entry, i) =>
      parseCombinationEntry(entry, "exclude", i),
    );
  }

  // --- maxParallel (optional) ----------------------------------------------
  if ("maxParallel" in raw && raw.maxParallel !== undefined) {
    if (!isPositiveInteger(raw.maxParallel)) {
      throw new Error('"maxParallel" must be a positive integer');
    }
    config.maxParallel = raw.maxParallel;
  }

  // --- failFast (optional) -------------------------------------------------
  if ("failFast" in raw && raw.failFast !== undefined) {
    if (typeof raw.failFast !== "boolean") {
      throw new Error('"failFast" must be a boolean');
    }
    config.failFast = raw.failFast;
  }

  // --- maxSize (optional) --------------------------------------------------
  if ("maxSize" in raw && raw.maxSize !== undefined) {
    if (!isNonNegativeInteger(raw.maxSize)) {
      throw new Error('"maxSize" must be a non-negative integer');
    }
    config.maxSize = raw.maxSize;
  }

  return config;
}

/**
 * Strict scalar equality used when matching filter values against combination
 * values. We compare by value and type so `18` (number) does not match `"18"`
 * (string) — this mirrors how GitHub treats matrix values.
 */
function valuesEqual(a: MatrixValue, b: MatrixValue): boolean {
  return a === b;
}

/**
 * Does `combo` satisfy the partial `filter`? True when every key in the filter
 * exists in the combination with an equal value. A filter that names only a
 * subset of keys therefore matches a whole slice of the matrix (e.g. an
 * `{ os: "windows-latest" }` filter matches every windows combination).
 */
export function matchesFilter(filter: Combination, combo: Combination): boolean {
  for (const [key, value] of Object.entries(filter)) {
    if (!(key in combo) || !valuesEqual(combo[key]!, value)) {
      return false;
    }
  }
  return true;
}

/**
 * Apply GitHub `exclude` semantics: drop every combination matched by ANY of
 * the exclude entries. Excludes are partial filters (see `matchesFilter`).
 * Returns a new array; the input is not mutated.
 */
export function applyExclude(
  combos: Combination[],
  excludes: Combination[],
): Combination[] {
  if (excludes.length === 0) return combos.slice();
  return combos.filter(
    (combo) => !excludes.some((exclude) => matchesFilter(exclude, combo)),
  );
}

/**
 * Apply GitHub `include` semantics. This is intentionally faithful to GitHub's
 * documented algorithm rather than a simple concat:
 *
 *  1. For each include entry, try to EXTEND the original base combinations.
 *     An entry extends a base combination when every key it shares with the
 *     original matrix axes (`matrixKeys`) matches that combination's value.
 *     The entry's remaining keys are merged in; previously-added (non-axis)
 *     keys may be overwritten by a later entry.
 *  2. Only the ORIGINAL base combinations are candidates for extension —
 *     combinations created by a previous include entry are never extended.
 *  3. An include entry that extends nothing becomes a new standalone
 *     combination appended after the base.
 *
 * `matrixKeys` is the set of axis names from the base matrix; it is what lets
 * us tell "this include narrows an existing axis" apart from "this include just
 * decorates rows with extra metadata".
 *
 * Returns a new array; inputs are not mutated.
 */
export function applyInclude(
  combos: Combination[],
  includes: Combination[],
  matrixKeys: string[],
): Combination[] {
  // Clone so we never mutate the caller's combinations.
  const result: Combination[] = combos.map((c) => ({ ...c }));
  // Only these original rows are eligible to be extended (rule 2).
  const baseCount = result.length;
  const matrixKeySet = new Set(matrixKeys);

  for (const include of includes) {
    // The axis keys this include constrains (keys that are real matrix axes).
    const axisConstraints = Object.entries(include).filter(([key]) =>
      matrixKeySet.has(key),
    );

    let extendedAny = false;
    for (let i = 0; i < baseCount; i++) {
      const combo = result[i]!;
      // Extend only when all axis constraints are satisfied by this row.
      const matches = axisConstraints.every(
        ([key, value]) => key in combo && valuesEqual(combo[key]!, value),
      );
      if (matches) {
        Object.assign(combo, include);
        extendedAny = true;
      }
    }

    // Matched nothing -> the include stands alone as a new combination (rule 3).
    if (!extendedAny) {
      result.push({ ...include });
    }
  }

  return result;
}

/**
 * Generate the complete GitHub Actions strategy from a validated config.
 *
 * Processing order mirrors GitHub exactly:
 *   1. expand the axes into the cartesian product,
 *   2. apply `exclude` to the product,
 *   3. apply `include` to what remains (so include can re-add an excluded row).
 *
 * After expansion the result is checked against `maxSize` (when configured) and
 * generation fails loudly rather than emitting an oversized matrix that GitHub
 * would reject at runtime. The returned object is shaped for direct use as a
 * `strategy:` block: the combinations live under `matrix.include`, with
 * `max-parallel` / `fail-fast` included only when the config sets them.
 */
export function generateMatrix(config: MatrixConfig): GeneratedStrategy {
  const axisKeys = Object.keys(config.matrix);

  const base = cartesianProduct(config.matrix);
  const afterExclude = applyExclude(base, config.exclude ?? []);
  const combinations = applyInclude(
    afterExclude,
    config.include ?? [],
    axisKeys,
  );

  const count = combinations.length;

  // Max-size safety valve. A zero limit is honoured too (it means "no jobs
  // allowed"), so we explicitly check for `undefined` rather than falsiness.
  if (config.maxSize !== undefined && count > config.maxSize) {
    throw new Error(
      `Generated matrix has ${count} combinations, which exceeds the ` +
        `configured maxSize of ${config.maxSize}. Reduce the number of axes ` +
        `or values, add exclude rules, or raise maxSize.`,
    );
  }

  const strategy: GeneratedStrategy = {
    matrix: { include: combinations },
    count,
  };
  if (config.maxParallel !== undefined) {
    strategy["max-parallel"] = config.maxParallel;
  }
  if (config.failFast !== undefined) {
    strategy["fail-fast"] = config.failFast;
  }
  return strategy;
}
