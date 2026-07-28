// Matrix generator: converts configuration into GitHub Actions build matrix format
// Supports OS options, language versions, feature flags, include/exclude rules, and limits

export class MatrixGenerator {
  constructor(defaultMaxSize = 256) {
    this.defaultMaxSize = defaultMaxSize;
  }

  generate(config) {
    // Determine the maximum allowed matrix size
    const maxSize = config.maxSize !== undefined ? config.maxSize : this.defaultMaxSize;

    // If include is explicitly provided, use it as-is
    if (config.include) {
      let matrix = { include: [...config.include] };

      // Apply excludes if provided
      if (config.exclude) {
        matrix.include = this._applyExcludes(matrix.include, config.exclude);
      }

      // Validate size
      if (matrix.include.length > maxSize) {
        throw new Error(
          `Matrix size ${matrix.include.length} exceeds maximum matrix size ${maxSize}`
        );
      }

      // Add optional properties
      if (config.failFast !== undefined) {
        matrix.failFast = config.failFast;
      }
      if (config.maxParallel !== undefined) {
        matrix.maxParallel = config.maxParallel;
      }

      return matrix;
    }

    // Generate matrix as product of dimensions
    const dimensions = this._extractDimensions(config);
    let combinations = this._generateProduct(dimensions);

    // Apply excludes if provided
    if (config.exclude) {
      combinations = this._applyExcludes(combinations, config.exclude);
    }

    // Validate size
    if (combinations.length > maxSize) {
      throw new Error(
        `Matrix size ${combinations.length} exceeds maximum matrix size ${maxSize}`
      );
    }

    // Build final matrix
    const matrix = { include: combinations };

    if (config.failFast !== undefined) {
      matrix.failFast = config.failFast;
    }
    if (config.maxParallel !== undefined) {
      matrix.maxParallel = config.maxParallel;
    }

    return matrix;
  }

  _extractDimensions(config) {
    // Extract all configuration keys that are arrays (except include/exclude)
    const dimensions = {};
    const skipKeys = new Set(['include', 'exclude', 'failFast', 'maxParallel', 'maxSize']);

    for (const [key, value] of Object.entries(config)) {
      if (!skipKeys.has(key) && Array.isArray(value)) {
        dimensions[key] = value;
      }
    }

    return dimensions;
  }

  _generateProduct(dimensions) {
    const dimensionKeys = Object.keys(dimensions);

    // If no dimensions, return empty array
    if (dimensionKeys.length === 0) {
      return [];
    }

    // Start with the first dimension
    let combinations = dimensions[dimensionKeys[0]].map(value => ({
      [dimensionKeys[0]]: value
    }));

    // Cross product with each remaining dimension
    for (let i = 1; i < dimensionKeys.length; i++) {
      const key = dimensionKeys[i];
      const values = dimensions[key];

      const newCombinations = [];
      for (const combo of combinations) {
        for (const value of values) {
          newCombinations.push({
            ...combo,
            [key]: value
          });
        }
      }
      combinations = newCombinations;
    }

    return combinations;
  }

  _applyExcludes(combinations, excludes) {
    // Filter out any combination that matches an exclude rule
    return combinations.filter(combo => {
      for (const excludeRule of excludes) {
        if (this._matchesRule(combo, excludeRule)) {
          return false; // Exclude this combination
        }
      }
      return true; // Keep this combination
    });
  }

  _matchesRule(combo, rule) {
    // Check if a combination matches an exclude/include rule
    for (const [key, value] of Object.entries(rule)) {
      if (combo[key] !== value) {
        return false;
      }
    }
    return true;
  }
}
