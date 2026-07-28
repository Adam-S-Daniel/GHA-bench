// Matrix generator for GitHub Actions
// Generates a build matrix from configuration describing OS options, language versions, and feature flags

/**
 * Generate a GitHub Actions strategy matrix from configuration.
 * @param {Object} config - Configuration object with arrays of options (e.g., { os: [...], node_version: [...] })
 * @param {Object} options - Matrix generation options
 * @param {number} options.maxSize - Maximum number of combinations allowed (default: 256)
 * @param {number} options.maxParallel - Maximum parallel jobs (optional)
 * @param {boolean} options.failFast - Fail fast on first job failure (default: true)
 * @param {Array} options.include - Additional configurations to include
 * @param {Array} options.exclude - Configurations to exclude
 * @returns {Object} GitHub Actions matrix object with include array and optional settings
 */
export function generateMatrix(config, options = {}) {
  const {
    maxSize = 256,
    maxParallel,
    failFast = true,
    include = [],
    exclude = []
  } = options;

  // Generate all combinations from config
  const combinations = cartesianProduct(Object.entries(config));

  // Check size limit
  if (combinations.length > maxSize) {
    throw new Error(
      `Matrix size ${combinations.length} exceeds maximum of ${maxSize}`
    );
  }

  // Build the matrix object
  const matrix = {
    include: combinations
  };

  // Add optional settings
  if (maxParallel !== undefined) {
    matrix.max_parallel = maxParallel;
  }

  if (failFast !== true) {
    matrix.fail_fast = failFast;
  }

  // Apply include rules
  if (include && include.length > 0) {
    const newCombinations = [...matrix.include];

    for (const inc of include) {
      // Check if this combination already exists
      const exists = newCombinations.some(combo =>
        Object.entries(inc).every(([key, value]) => combo[key] === value)
      );

      if (!exists) {
        newCombinations.push(inc);
      }
    }

    // Re-check size after includes
    if (newCombinations.length > maxSize) {
      throw new Error(
        `Matrix size ${newCombinations.length} exceeds maximum of ${maxSize}`
      );
    }

    matrix.include = newCombinations;
  }

  // Apply exclude rules
  if (exclude && exclude.length > 0) {
    matrix.include = matrix.include.filter(combo => {
      // Keep combo if it doesn't match any exclude pattern
      return !exclude.some(excl =>
        Object.entries(excl).every(([key, value]) => combo[key] === value)
      );
    });
  }

  return matrix;
}

/**
 * Cartesian product of arrays from key-value pairs.
 * Converts [{key: 'os', value: ['ubuntu', 'macos']}, {key: 'node', value: ['18', '20']}]
 * to [{os: 'ubuntu', node: '18'}, {os: 'ubuntu', node: '20'}, ...]
 * @param {Array} entries - Array of [key, array] pairs
 * @returns {Array} Array of objects representing all combinations
 */
function cartesianProduct(entries) {
  if (entries.length === 0) return [];

  // Filter out any entries with empty arrays
  const validEntries = entries.filter(([, values]) =>
    Array.isArray(values) && values.length > 0
  );

  if (validEntries.length === 0) return [];

  // Start with first key-value pairs
  let products = validEntries[0][1].map(value => ({
    [validEntries[0][0]]: value
  }));

  // Multiply with remaining key-value pairs
  for (let i = 1; i < validEntries.length; i++) {
    const [key, values] = validEntries[i];
    const newProducts = [];

    for (const product of products) {
      for (const value of values) {
        newProducts.push({
          ...product,
          [key]: value
        });
      }
    }

    products = newProducts;
  }

  return products;
}

/**
 * CLI entry point: reads config from stdin or file and outputs matrix JSON
 */
export async function main() {
  try {
    // For now, read from stdin (will be used by workflow)
    let input = '';

    // Check if input is provided as argument
    if (process.argv[2]) {
      const fs = await import('fs');
      input = fs.readFileSync(process.argv[2], 'utf-8');
    } else {
      // Read from stdin
      input = await readStdin();
    }

    const configData = JSON.parse(input);
    const matrix = generateMatrix(configData.config, configData.options);

    console.log(JSON.stringify(matrix, null, 2));
    process.exit(0);
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

/**
 * Read from stdin until EOF
 */
function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';

    process.stdin.setEncoding('utf-8');
    process.stdin.on('readable', () => {
      let chunk;
      while ((chunk = process.stdin.read()) !== null) {
        data += chunk;
      }
    });

    process.stdin.on('end', () => {
      resolve(data);
    });

    process.stdin.on('error', reject);
  });
}

// Run CLI if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
