// Interface for matrix configuration
export interface MatrixConfig {
  os?: string[];
  nodeVersion?: string[];
  pythonVersion?: string[];
  features?: string[];
  [key: string]: string[] | undefined;
}

// Interface for matrix options
export interface MatrixOptions {
  include?: Array<Record<string, string>>;
  exclude?: Array<Record<string, string>>;
  maxParallel?: number;
  failFast?: boolean;
  maxSize?: number;
}

// Interface for matrix strategy result
export interface MatrixStrategy {
  include: Array<Record<string, string>>;
  exclude?: Array<Record<string, string>>;
  "max-parallel"?: number;
  "fail-fast"?: boolean;
}

// Generate all combinations of config values
export function generateMatrix(
  config: MatrixConfig,
  options?: MatrixOptions
): MatrixStrategy {
  const maxSize = options?.maxSize || 256;

  // Get all keys from config (excluding undefined values)
  const keys = Object.keys(config).filter((key) => config[key]);

  if (keys.length === 0) {
    return { include: [] };
  }

  // Get all values for each key
  const values = keys.map((key) => config[key]!);

  // Generate cartesian product
  let include = cartesianProduct(values).map((combination) => {
    const obj: Record<string, string> = {};
    keys.forEach((key, idx) => {
      obj[key] = combination[idx];
    });
    return obj;
  });

  // Validate size before applying options
  if (include.length > maxSize) {
    throw new Error(
      `Matrix size (${include.length}) exceeds maximum allowed size (${maxSize})`
    );
  }

  // Add include rules if provided
  if (options?.include) {
    include = [...include, ...options.include];
  }

  // Build result object
  const result: MatrixStrategy = { include };

  // Add exclude rules if provided
  if (options?.exclude && options.exclude.length > 0) {
    result.exclude = options.exclude;
  }

  // Add max-parallel if provided
  if (options?.maxParallel !== undefined) {
    result["max-parallel"] = options.maxParallel;
  }

  // Add fail-fast if provided
  if (options?.failFast !== undefined) {
    result["fail-fast"] = options.failFast;
  }

  return result;
}

// Helper function to generate cartesian product
function cartesianProduct(arrays: string[][]): string[][] {
  if (arrays.length === 0) return [];
  if (arrays.length === 1) return arrays[0].map((val) => [val]);

  const result: string[][] = [];
  const [first, ...rest] = arrays;
  const subProduct = cartesianProduct(rest);

  first.forEach((val) => {
    subProduct.forEach((sub) => {
      result.push([val, ...sub]);
    });
  });

  return result;
}
