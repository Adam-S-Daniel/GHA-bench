interface MatrixConfig {
  [key: string]: string[] | number | boolean | object[];
  maxSize?: number;
  maxParallel?: number;
  failFast?: boolean;
  include?: Record<string, string>[];
  exclude?: Record<string, string>[];
}

interface MatrixResult {
  include: Record<string, string>[];
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}

// Generate all combinations from configuration keys/values
function generateCombinations(
  config: MatrixConfig
): Record<string, string>[] {
  const keys = Object.keys(config).filter(
    (k) =>
      !["maxSize", "maxParallel", "failFast", "include", "exclude"].includes(
        k
      ) && Array.isArray(config[k])
  );

  if (keys.length === 0) {
    return [];
  }

  const values = keys.map((k) => (config[k] as string[]).map((v) => ({ [k]: v })));

  // Cartesian product
  return values.reduce((acc, curr) => {
    if (acc.length === 0) {
      return curr;
    }
    return acc.flatMap((a) => curr.map((c) => ({ ...a, ...c })));
  });
}

// Check if a combination matches an exclusion rule
function matchesExclusionRule(
  combination: Record<string, string>,
  rule: Record<string, string>
): boolean {
  return Object.entries(rule).every(([key, value]) => combination[key] === value);
}

// Apply exclude rules to combinations
function applyExclusions(
  combinations: Record<string, string>[],
  exclude: Record<string, string>[]
): Record<string, string>[] {
  return combinations.filter(
    (combo) => !exclude.some((rule) => matchesExclusionRule(combo, rule))
  );
}

// Merge include array with combinations
function mergeIncludes(
  combinations: Record<string, string>[],
  include: Record<string, string>[]
): Record<string, string>[] {
  const combined = [...combinations];

  // Add include items that aren't already in combinations
  for (const item of include) {
    const exists = combined.some((c) =>
      Object.entries(item).every(([key, value]) => c[key] === value)
    );

    if (!exists) {
      combined.push(item);
    }
  }

  return combined;
}

export function generateMatrix(config: MatrixConfig): MatrixResult {
  const maxSize = config.maxSize ?? 1000;
  const exclude = (config.exclude as Record<string, string>[]) ?? [];
  const include = (config.include as Record<string, string>[]) ?? [];

  // Generate base combinations
  let combinations = generateCombinations(config);

  // Apply exclusions
  combinations = applyExclusions(combinations, exclude);

  // Apply includes
  combinations = mergeIncludes(combinations, include);

  // Validate matrix size
  if (combinations.length > maxSize) {
    throw new Error(
      `Matrix size (${combinations.length}) exceeds maximum allowed (${maxSize})`
    );
  }

  const result: MatrixResult = {
    include: combinations,
  };

  // Add optional fields
  if (config.maxParallel !== undefined) {
    result["max-parallel"] = config.maxParallel;
  }

  if (config.failFast !== undefined) {
    result["fail-fast"] = config.failFast;
  }

  return result;
}
