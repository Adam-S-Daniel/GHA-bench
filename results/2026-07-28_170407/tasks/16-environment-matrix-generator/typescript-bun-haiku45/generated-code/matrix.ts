// Matrix configuration interface
export interface MatrixConfig {
  os?: string[];
  nodeVersion?: string[];
  python?: string[];
  includeRules?: MatrixEntry[];
  excludeRules?: MatrixEntry[];
  maxParallel?: number;
  failFast?: boolean;
  maxSize?: number;
}

// Individual matrix entry
export interface MatrixEntry {
  os?: string;
  nodeVersion?: string;
  python?: string;
  [key: string]: string | undefined;
}

// Generated matrix result
export interface MatrixResult {
  matrix: {
    include: MatrixEntry[];
    exclude?: MatrixEntry[];
  };
  maxParallel?: number;
  failFast?: boolean;
}

export function generateMatrix(config: MatrixConfig): MatrixResult {
  const include: MatrixEntry[] = [];

  // Generate all combinations from the config
  const osList = config.os || [];
  const nodeVersions = config.nodeVersion || [];
  const pythonVersions = config.python || [];

  if (osList.length > 0 && nodeVersions.length > 0) {
    for (const os of osList) {
      for (const nodeVersion of nodeVersions) {
        include.push({ os, nodeVersion });
      }
    }
  } else if (osList.length > 0) {
    for (const os of osList) {
      include.push({ os });
    }
  } else if (nodeVersions.length > 0) {
    for (const nodeVersion of nodeVersions) {
      include.push({ nodeVersion });
    }
  }

  // Validate matrix size
  const maxSize = config.maxSize ?? 256;
  if (include.length > maxSize) {
    throw new Error(
      `Matrix size ${include.length} exceeds maximum allowed size ${maxSize}`
    );
  }

  const result: MatrixResult = {
    matrix: {
      include,
    },
  };

  if (config.excludeRules && config.excludeRules.length > 0) {
    result.matrix.exclude = config.excludeRules;
  }

  if (config.maxParallel !== undefined) {
    result.maxParallel = config.maxParallel;
  }

  if (config.failFast !== undefined) {
    result.failFast = config.failFast;
  }

  return result;
}

export function serializeMatrixJSON(result: MatrixResult): string {
  return JSON.stringify(result, null, 2);
}
