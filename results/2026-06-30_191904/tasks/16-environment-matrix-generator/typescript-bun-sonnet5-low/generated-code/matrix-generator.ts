// Generates a GitHub Actions build matrix from a config describing
// dimensions (os, language versions, feature flags, etc), include/exclude
// rules, max-parallel, and fail-fast settings.

export type MatrixValue = string | number | boolean;
export type MatrixCombination = Record<string, MatrixValue>;

export interface MatrixConfig {
  /** Named dimensions, each an array of possible values (cartesian product). */
  dimensions: Record<string, MatrixValue[]>;
  /** Extra combinations to add (or extra keys to merge onto matching rows), per GitHub Actions `include` semantics. */
  include?: MatrixCombination[];
  /** Combinations to remove; a row is excluded if ALL specified keys match. */
  exclude?: MatrixCombination[];
  /** Maximum number of concurrent jobs. */
  maxParallel?: number;
  /** Whether to cancel all jobs if one fails. Defaults to true (GitHub Actions default). */
  failFast?: boolean;
  /** Maximum allowed number of generated combinations (safety limit). */
  maxSize?: number;
}

export interface StrategyMatrix {
  matrix: {
    include: MatrixCombination[];
  };
  "fail-fast"?: boolean;
  "max-parallel"?: number;
}

const DEFAULT_MAX_SIZE = 256; // GitHub Actions hard limit on matrix jobs

/** Computes the cartesian product of the given named dimensions. */
function cartesianProduct(dimensions: Record<string, MatrixValue[]>): MatrixCombination[] {
  const keys = Object.keys(dimensions);
  if (keys.length === 0) return [];

  return keys.reduce<MatrixCombination[]>(
    (acc, key) => {
      const values = dimensions[key];
      const next: MatrixCombination[] = [];
      for (const combo of acc) {
        for (const value of values) {
          next.push({ ...combo, [key]: value });
        }
      }
      return next;
    },
    [{}]
  );
}

/** Returns true if `combo` matches every key/value pair in `filter`. */
function matches(combo: MatrixCombination, filter: MatrixCombination): boolean {
  return Object.entries(filter).every(([key, value]) => combo[key] === value);
}

/** Applies GitHub Actions `exclude` semantics: drop any row matching all keys of an exclude entry. */
function applyExclude(rows: MatrixCombination[], exclude: MatrixCombination[]): MatrixCombination[] {
  return rows.filter((row) => !exclude.some((rule) => matches(row, rule)));
}

/**
 * Applies GitHub Actions `include` semantics: for each include entry, if it matches
 * one or more existing rows (on the keys the entry shares with those rows), merge its
 * extra keys into those rows. If it matches no existing rows, it's appended as a new row.
 */
function applyInclude(rows: MatrixCombination[], include: MatrixCombination[]): MatrixCombination[] {
  const result = [...rows];

  for (const entry of include) {
    const entryKeys = Object.keys(entry);
    const sharedKeyMatches = result
      .map((row, idx) => ({ row, idx }))
      .filter(({ row }) => {
        const sharedKeys = entryKeys.filter((k) => k in row);
        if (sharedKeys.length === 0) return false;
        return sharedKeys.every((k) => row[k] === entry[k]);
      });

    if (sharedKeyMatches.length > 0) {
      for (const { idx } of sharedKeyMatches) {
        result[idx] = { ...result[idx], ...entry };
      }
    } else {
      result.push({ ...entry });
    }
  }

  return result;
}

export interface GenerateMatrixResult {
  matrix: {
    include: MatrixCombination[];
  };
  "fail-fast": boolean;
  "max-parallel"?: number;
}

/** Generates a GitHub Actions strategy matrix from the given config. */
export function generateMatrix(config: MatrixConfig): GenerateMatrixResult {
  if (!config.dimensions || Object.keys(config.dimensions).length === 0) {
    throw new Error("MatrixConfig must define at least one dimension");
  }

  for (const [key, values] of Object.entries(config.dimensions)) {
    if (!Array.isArray(values) || values.length === 0) {
      throw new Error(`Dimension "${key}" must be a non-empty array of values`);
    }
  }

  let rows = cartesianProduct(config.dimensions);

  if (config.exclude && config.exclude.length > 0) {
    rows = applyExclude(rows, config.exclude);
  }

  if (config.include && config.include.length > 0) {
    rows = applyInclude(rows, config.include);
  }

  const maxSize = config.maxSize ?? DEFAULT_MAX_SIZE;
  if (rows.length > maxSize) {
    throw new Error(
      `Generated matrix has ${rows.length} combinations, which exceeds the maximum allowed size of ${maxSize}`
    );
  }

  if (rows.length === 0) {
    throw new Error("Generated matrix has zero combinations after applying exclude rules");
  }

  if (config.maxParallel !== undefined && config.maxParallel < 1) {
    throw new Error(`max-parallel must be a positive integer, got ${config.maxParallel}`);
  }

  const result: GenerateMatrixResult = {
    matrix: { include: rows },
    "fail-fast": config.failFast ?? true,
  };

  if (config.maxParallel !== undefined) {
    result["max-parallel"] = config.maxParallel;
  }

  return result;
}

// CLI entry point: reads config JSON from argv[2] (file path) or stdin, prints matrix JSON.
if (import.meta.main) {
  const path = process.argv[2];
  let raw: string;
  if (path) {
    raw = await Bun.file(path).text();
  } else {
    raw = await new Response(Bun.stdin.stream()).text();
  }

  let config: MatrixConfig;
  try {
    config = JSON.parse(raw);
  } catch (err) {
    console.error(`Failed to parse config JSON: ${(err as Error).message}`);
    process.exit(1);
  }

  try {
    const result = generateMatrix(config);
    console.log(JSON.stringify(result, null, 2));
  } catch (err) {
    console.error(`Failed to generate matrix: ${(err as Error).message}`);
    process.exit(1);
  }
}
