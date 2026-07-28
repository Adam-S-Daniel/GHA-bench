// Matrix configuration describing OS options, versions, and flags
export interface MatrixConfig {
  os?: string[];
  nodeVersion?: string[];
  pythonVersion?: string[];
  rubyVersion?: string[];
  features?: Record<string, boolean[] | string[]>;
  include?: Record<string, string | number | boolean>[];
  exclude?: Record<string, string | number | boolean>[];
  failFast?: boolean;
  maxParallel?: number;
  maxSize?: number;
}

// Single matrix entry
interface MatrixEntry {
  [key: string]: string | number | boolean;
}

// GitHub Actions strategy configuration
interface Strategy {
  "fail-fast"?: boolean;
  "max-parallel"?: number;
}

// Complete matrix output suitable for GitHub Actions
export interface MatrixOutput {
  matrix: {
    include: MatrixEntry[];
    exclude?: Record<string, string | number | boolean>[];
  };
  strategy?: Strategy;
}

// Generate all combinations using cartesian product
function cartesianProduct(
  arrays: Record<string, (string | number | boolean)[]>
): MatrixEntry[] {
  const keys = Object.keys(arrays);
  const values = keys.map((key) => arrays[key]);

  if (values.some((arr) => arr.length === 0)) {
    throw new Error("Cannot generate matrix from empty dimension");
  }

  const combinations: MatrixEntry[] = [];
  const indices = new Array(values.length).fill(0);

  let done = false;
  while (!done) {
    const entry: MatrixEntry = {};
    for (let i = 0; i < keys.length; i++) {
      entry[keys[i]] = values[i][indices[i]];
    }
    combinations.push(entry);

    let pos = indices.length - 1;
    while (pos >= 0 && indices[pos] === values[pos].length - 1) {
      indices[pos] = 0;
      pos--;
    }
    if (pos < 0) {
      done = true;
    } else {
      indices[pos]++;
    }
  }

  return combinations;
}

// Check if an entry matches an exclude rule
function matchesExcludeRule(
  entry: MatrixEntry,
  rule: Record<string, string | number | boolean>
): boolean {
  return Object.entries(rule).every(([key, value]) => entry[key] === value);
}

// Generate build matrix from configuration
export function generateMatrix(config: MatrixConfig): MatrixOutput {
  const maxSize = config.maxSize ?? 256;

  // Known dimension names that should be validated for emptiness
  const knownDimensions = ["os", "nodeVersion", "pythonVersion", "rubyVersion"];

  // Check for explicitly empty known dimensions
  for (const dim of knownDimensions) {
    const dimKey = dim as keyof MatrixConfig;
    if (config[dimKey] !== undefined && Array.isArray(config[dimKey]) &&
        (config[dimKey] as any).length === 0) {
      throw new Error(`Configuration dimension '${dim}' is empty`);
    }
  }

  // Collect all dimension keys and values
  const dimensions: Record<string, (string | number | boolean)[]> = {};

  // Add known dimensions
  if (config.os && config.os.length > 0) {
    dimensions.os = config.os;
  }
  if (config.nodeVersion && config.nodeVersion.length > 0) {
    dimensions.nodeVersion = config.nodeVersion;
  }
  if (config.pythonVersion && config.pythonVersion.length > 0) {
    dimensions.pythonVersion = config.pythonVersion;
  }
  if (config.rubyVersion && config.rubyVersion.length > 0) {
    dimensions.rubyVersion = config.rubyVersion;
  }

  // Add feature flags
  if (config.features) {
    Object.entries(config.features).forEach(([key, values]) => {
      if (Array.isArray(values) && values.length > 0) {
        dimensions[key] = values;
      }
    });
  }

  // Add any other arbitrary array dimensions from config
  const reservedKeys = new Set([
    ...knownDimensions,
    "features",
    "include",
    "exclude",
    "failFast",
    "maxParallel",
    "maxSize",
  ]);

  for (const [key, value] of Object.entries(config)) {
    if (!reservedKeys.has(key) && Array.isArray(value) && value.length > 0) {
      dimensions[key] = value as (string | number | boolean)[];
    }
  }

  // Check for empty dimensions
  const dimKeys = Object.keys(dimensions);
  if (dimKeys.length === 0) {
    throw new Error("Configuration must have at least one non-empty dimension");
  }

  // Generate cartesian product
  let combinations = cartesianProduct(dimensions);

  // Apply exclude rules - filter out matching combinations
  if (config.exclude && config.exclude.length > 0) {
    combinations = combinations.filter(
      (entry) => !config.exclude!.some((rule) => matchesExcludeRule(entry, rule))
    );
  }

  // Validate matrix size
  if (combinations.length > maxSize) {
    throw new Error(
      `Generated matrix (${combinations.length} combinations) exceeds maximum size of ${maxSize}`
    );
  }

  // Apply user-provided includes
  if (config.include && config.include.length > 0) {
    combinations = [...combinations, ...config.include];
  }

  const output: MatrixOutput = {
    matrix: {
      include: combinations,
    },
  };

  // Add exclude rules if provided
  if (config.exclude && config.exclude.length > 0) {
    output.matrix.exclude = config.exclude;
  }

  // Add strategy configuration
  const strategy: Strategy = {};
  if (config.failFast !== undefined) {
    strategy["fail-fast"] = config.failFast;
  }
  if (config.maxParallel !== undefined) {
    strategy["max-parallel"] = config.maxParallel;
  }

  if (Object.keys(strategy).length > 0) {
    output.strategy = strategy;
  }

  return output;
}

// CLI entry point
if (import.meta.main) {
  const configPath = process.argv[2];

  if (!configPath) {
    console.error("Usage: generator.ts <config.json>");
    process.exit(1);
  }

  try {
    const configFile = await Bun.file(configPath).text();
    const config: MatrixConfig = JSON.parse(configFile);
    const result = generateMatrix(config);
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error("Unknown error occurred");
    }
    process.exit(1);
  }
}
