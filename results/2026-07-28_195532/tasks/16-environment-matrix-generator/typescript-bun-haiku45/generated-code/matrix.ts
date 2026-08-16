// Interface for matrix generator configuration
export interface MatrixConfig {
  [key: string]: any;
  maxSize?: number;
  include?: Record<string, any>[];
  exclude?: Record<string, any>[];
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}

// Interface for generated matrix output
export interface GeneratedMatrix {
  include: Record<string, any>[];
  exclude?: Record<string, any>[];
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}

/**
 * Generates a GitHub Actions matrix from configuration options.
 * Supports include/exclude rules, max-parallel limits, and fail-fast configuration.
 * Validates that the matrix doesn't exceed maxSize.
 */
export function generateMatrix(config: MatrixConfig): GeneratedMatrix {
  // Get all non-metadata keys (actual matrix axes)
  const matrixKeys = Object.keys(config).filter(
    (k) =>
      ![
        "include",
        "exclude",
        "maxSize",
        "max-parallel",
        "fail-fast",
      ].includes(k)
  );

  // Validate that no matrix axis is empty
  for (const key of matrixKeys) {
    if (!Array.isArray(config[key]) || config[key].length === 0) {
      throw new Error(`Matrix axis "${key}" must be a non-empty array`);
    }
  }

  // Calculate the size of the cartesian product
  let matrixSize = 1;
  for (const key of matrixKeys) {
    matrixSize *= config[key].length;
  }

  // Check max size constraint
  const maxSize = config.maxSize ?? Infinity;
  if (matrixSize > maxSize) {
    throw new Error(
      `Matrix size (${matrixSize}) exceeds maximum allowed (${maxSize})`
    );
  }

  // Generate cartesian product
  const combinations = generateCombinations(
    matrixKeys,
    config
  );

  // Build the result
  const result: GeneratedMatrix = {
    include: combinations,
  };

  // Add exclude rules if present
  if (config.exclude && Array.isArray(config.exclude)) {
    result.exclude = config.exclude;
    result.include = result.include.filter(
      (combo) => !matchesExclude(combo, config.exclude)
    );
  }

  // Add include rules if present
  if (config.include && Array.isArray(config.include)) {
    result.include = [...result.include, ...config.include];
  }

  // Add optional configuration
  if (config["max-parallel"] !== undefined) {
    result["max-parallel"] = config["max-parallel"];
  }

  if (config["fail-fast"] !== undefined) {
    result["fail-fast"] = config["fail-fast"];
  }

  return result;
}

// Generate all combinations of matrix axes (cartesian product)
function generateCombinations(
  keys: string[],
  config: MatrixConfig
): Record<string, any>[] {
  if (keys.length === 0) {
    return [{}];
  }

  const [firstKey, ...restKeys] = keys;
  const restCombinations = generateCombinations(restKeys, config);
  const combinations: Record<string, any>[] = [];

  for (const value of config[firstKey]) {
    for (const combo of restCombinations) {
      combinations.push({
        [firstKey]: value,
        ...combo,
      });
    }
  }

  return combinations;
}

// Check if a combination matches any exclude rule
function matchesExclude(
  combo: Record<string, any>,
  excludeRules: Record<string, any>[]
): boolean {
  return excludeRules.some((rule) => matchesRule(combo, rule));
}

// Check if a combination matches a rule (all keys in rule match in combo)
function matchesRule(
  combo: Record<string, any>,
  rule: Record<string, any>
): boolean {
  return Object.entries(rule).every(([key, value]) => combo[key] === value);
}
