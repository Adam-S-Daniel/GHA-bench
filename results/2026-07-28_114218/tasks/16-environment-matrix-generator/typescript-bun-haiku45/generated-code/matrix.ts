export interface MatrixConfig {
  os: string[];
  languages: string[];
  features?: string[];
  nodeVersions?: string[];
  include?: Record<string, string | number | boolean>[];
  exclude?: Record<string, string | number | boolean>[];
  maxParallel?: number;
  failFast?: boolean;
  maxSize?: number;
}

export interface BuildMatrix {
  matrix: {
    include: Record<string, string | number | boolean>[];
    exclude?: Record<string, string | number | boolean>[];
  };
  maxParallel?: number;
  failFast?: boolean;
}

/**
 * Generate a cartesian product of matrix axes.
 * Creates all combinations of os × languages × features × nodeVersions.
 */
export function generateMatrix(config: MatrixConfig): BuildMatrix {
  validateConfig(config);

  const axes = buildAxes(config);
  let combinations = cartesianProduct(axes);

  // Apply exclusions
  if (config.exclude && config.exclude.length > 0) {
    combinations = applyExclusions(combinations, config.exclude);
  }

  // Apply inclusions (add custom rows)
  if (config.include && config.include.length > 0) {
    combinations = [...combinations, ...config.include];
  }

  // Validate matrix size
  const maxSize = config.maxSize ?? 1000;
  if (combinations.length > maxSize) {
    throw new Error(
      `Matrix size (${combinations.length}) exceeds maximum allowed (${maxSize})`
    );
  }

  const result: BuildMatrix = {
    matrix: {
      include: combinations,
    },
  };

  if (config.exclude && config.exclude.length > 0) {
    result.matrix.exclude = config.exclude;
  }

  if (config.maxParallel !== undefined) {
    result.maxParallel = config.maxParallel;
  }

  if (config.failFast !== undefined) {
    result.failFast = config.failFast;
  }

  return result;
}

function validateConfig(config: MatrixConfig): void {
  if (!config.os || !Array.isArray(config.os)) {
    throw new Error("Config must have 'os' array");
  }
  if (!config.languages || !Array.isArray(config.languages)) {
    throw new Error("Config must have 'languages' array");
  }
}

function buildAxes(config: MatrixConfig): Record<string, string[]> {
  const axes: Record<string, string[]> = {};

  if (config.os.length > 0) {
    axes.os = config.os;
  }
  if (config.languages.length > 0) {
    axes.language = config.languages;
  }
  if (config.features && config.features.length > 0) {
    axes.feature = config.features;
  }
  if (config.nodeVersions && config.nodeVersions.length > 0) {
    axes.nodeVersion = config.nodeVersions;
  }

  return axes;
}

/**
 * Cartesian product: generates all combinations of values across axes.
 * For axes {a: [1,2], b: [x,y]}, produces [{a:1,b:x}, {a:1,b:y}, {a:2,b:x}, {a:2,b:y}]
 */
function cartesianProduct(
  axes: Record<string, string[]>
): Record<string, string | number | boolean>[] {
  const axisNames = Object.keys(axes);

  if (axisNames.length === 0) {
    return [];
  }

  const results: Record<string, string | number | boolean>[] = [{}];

  for (const axisName of axisNames) {
    const axisValues = axes[axisName];
    const newResults: Record<string, string | number | boolean>[] = [];

    for (const existing of results) {
      for (const value of axisValues) {
        newResults.push({
          ...existing,
          [axisName]: value,
        });
      }
    }

    results.length = 0;
    results.push(...newResults);
  }

  return results;
}

/**
 * Remove combinations that match any exclusion rule.
 * A combination is excluded if all key-value pairs in the exclusion rule match.
 */
function applyExclusions(
  combinations: Record<string, string | number | boolean>[],
  exclusions: Record<string, string | number | boolean>[]
): Record<string, string | number | boolean>[] {
  return combinations.filter((combo) => {
    for (const exclusion of exclusions) {
      if (matchesRule(combo, exclusion)) {
        return false;
      }
    }
    return true;
  });
}

/**
 * Check if a combination matches a rule (all keys in rule match in combo).
 */
function matchesRule(
  combo: Record<string, string | number | boolean>,
  rule: Record<string, string | number | boolean>
): boolean {
  for (const key of Object.keys(rule)) {
    if (combo[key] !== rule[key]) {
      return false;
    }
  }
  return true;
}

/**
 * Load config from JSON file and generate matrix.
 */
export async function loadConfigAndGenerate(
  configPath: string
): Promise<BuildMatrix> {
  const file = await Bun.file(configPath).text();
  const config: MatrixConfig = JSON.parse(file);
  return generateMatrix(config);
}

/**
 * Main CLI entry point.
 */
export async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error("Usage: bun matrix.ts <config-file.json>");
    process.exit(1);
  }

  const configPath = args[0];

  try {
    const result = await loadConfigAndGenerate(configPath);
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    } else {
      console.error("Unknown error");
    }
    process.exit(1);
  }
}

// Run main if invoked directly
if (import.meta.main) {
  main();
}
