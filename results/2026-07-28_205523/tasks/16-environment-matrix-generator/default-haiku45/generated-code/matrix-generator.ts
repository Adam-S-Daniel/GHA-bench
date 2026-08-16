// Environment Matrix Generator for GitHub Actions
// Generates strategy.matrix JSON from configuration with support for
// include/exclude rules, max-parallel limits, and fail-fast configuration

export interface GitHubMatrix {
  include: Record<string, any>[];
  exclude?: Record<string, any>[];
  "fail-fast"?: boolean;
  "max-parallel"?: number;
}

export interface MatrixConfig {
  [key: string]: any;
  include?: Record<string, any>[];
  exclude?: Record<string, any>[];
  failFast?: boolean;
  maxParallel?: number;
  maxSize?: number;
}

function cartesianProduct(arrays: any[][]): any[][] {
  if (arrays.length === 0) return [[]];
  if (arrays.some((arr) => arr.length === 0)) return [];

  const result: any[][] = [];
  const indices = new Array(arrays.length).fill(0);

  while (true) {
    const current = indices.map((i, j) => arrays[j][i]);
    result.push(current);

    let pos = arrays.length - 1;
    while (pos >= 0 && indices[pos] === arrays[pos].length - 1) {
      indices[pos] = 0;
      pos--;
    }

    if (pos < 0) break;
    indices[pos]++;
  }

  return result;
}

function matchesExcludeRule(
  item: Record<string, any>,
  rule: Record<string, any>
): boolean {
  // Match if all properties specified in the rule match the item
  return Object.entries(rule).every(([key, value]) => {
    return item.hasOwnProperty(key) && item[key] === value;
  });
}

export function generateMatrix(config: MatrixConfig): GitHubMatrix {
  // Collect special config keys
  const configInclude = config.include || [];
  const configExclude = config.exclude || [];
  const { failFast, maxParallel, maxSize } = config;

  // Collect all dimension arrays (keys that are arrays with length > 0, excluding special keys)
  const specialKeys = ["include", "exclude", "failFast", "maxParallel", "maxSize"];
  const dimensions: { [key: string]: any[] } = {};
  const dimensionNames: string[] = [];

  for (const [key, value] of Object.entries(config)) {
    // Skip special config keys
    if (specialKeys.includes(key)) {
      continue;
    }
    // Only process array values with items
    if (Array.isArray(value) && value.length > 0) {
      dimensions[key] = value;
      dimensionNames.push(key);
    }
  }

  let combinations: Record<string, any>[] = [];

  if (dimensionNames.length > 0) {
    // Get arrays in consistent order
    const arrays = dimensionNames.map((name) => dimensions[name]);

    // Generate all combinations via Cartesian product
    const products = cartesianProduct(arrays);

    combinations = products.map((values) => {
      const item: Record<string, any> = {};
      dimensionNames.forEach((name, i) => {
        item[name] = values[i];
      });
      return item;
    });
  }

  // Apply exclude rules - remove items that match any exclude rule
  let filtered = combinations.filter(
    (item) => !configExclude.some((rule) => matchesExcludeRule(item, rule))
  );

  // Combine with include items
  const allItems = [...filtered, ...configInclude];

  // Validate matrix size
  if (maxSize && allItems.length > maxSize) {
    throw new Error(
      `Matrix size ${allItems.length} exceeds maximum allowed size ${maxSize}`
    );
  }

  // Build the output matrix
  const matrix: GitHubMatrix = {
    include: allItems,
  };

  if (failFast !== undefined) {
    matrix["fail-fast"] = failFast;
  }

  if (maxParallel !== undefined) {
    matrix["max-parallel"] = maxParallel;
  }

  return matrix;
}

// CLI interface for reading config from JSON input
async function main() {
  if (Bun.argv.length < 3) {
    console.error("Usage: matrix-generator.ts <config.json>");
    process.exit(1);
  }

  const configPath = Bun.argv[2];

  try {
    const configFile = await Bun.file(configPath).text();
    const config: MatrixConfig = JSON.parse(configFile);

    const matrix = generateMatrix(config);
    console.log(JSON.stringify(matrix, null, 2));
  } catch (error) {
    if (error instanceof Error) {
      console.error(`Error: ${error.message}`);
    }
    process.exit(1);
  }
}

if (import.meta.main) {
  main();
}
