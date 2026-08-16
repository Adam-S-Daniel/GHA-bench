# Environment Matrix Generator

A Node.js utility for generating GitHub Actions build matrices from configuration. Supports include/exclude rules, max-parallel limits, fail-fast configuration, and comprehensive validation.

## Features

- **Cartesian Product Generation**: Automatically generates all combinations of OS options, language versions, and feature flags
- **Include Rules**: Add custom configurations to the matrix
- **Exclude Rules**: Remove specific configurations from the generated matrix
- **Max-Parallel Limit**: Configure maximum number of parallel jobs
- **Fail-Fast Control**: Set whether to fail immediately on first job failure
- **Size Validation**: Prevents matrices from exceeding configurable size limits (default 256 combinations)
- **JSON Output**: Generates valid GitHub Actions `strategy.matrix` JSON
- **Comprehensive Error Handling**: Meaningful error messages for configuration issues

## Installation

```bash
npm install
```

## Usage

### CLI

```bash
# From file
node src/index.js config.json

# From stdin
cat config.json | node src/index.js

# Example config.json
{
  "config": {
    "os": ["ubuntu-latest", "macos-latest"],
    "node_version": ["18", "20"]
  },
  "options": {
    "maxParallel": 2,
    "failFast": true,
    "exclude": [
      { "os": "macos-latest", "node_version": "18" }
    ]
  }
}
```

### Programmatic API

```javascript
import { generateMatrix } from './src/index.js';

const matrix = generateMatrix({
  os: ['ubuntu-latest', 'macos-latest'],
  node_version: ['18', '20']
}, {
  maxParallel: 4,
  failFast: false,
  exclude: [
    { os: 'macos-latest', node_version: '18' }
  ]
});

console.log(JSON.stringify(matrix, null, 2));
```

## Output

The generator produces a GitHub Actions matrix object:

```json
{
  "include": [
    { "os": "ubuntu-latest", "node_version": "18" },
    { "os": "ubuntu-latest", "node_version": "20" },
    { "os": "macos-latest", "node_version": "20" }
  ],
  "max_parallel": 4,
  "fail_fast": false
}
```

## Configuration Options

### Config Parameters

- **os** (array): List of OS values
- **node_version** (array): List of Node.js versions
- **arch** (array): List of architectures
- **Any custom field** (array): Arbitrary dimensions for the matrix

### Options

- **maxSize** (number, default: 256): Maximum combinations allowed before error
- **maxParallel** (number, optional): Maximum parallel jobs in GitHub Actions
- **failFast** (boolean, default: true): Whether to fail on first job failure
- **include** (array): Additional configurations to add to matrix
- **exclude** (array): Configurations to remove from matrix

## Testing

### Run All Tests

```bash
npm test
```

This runs 22 tests covering:
- Basic matrix generation (unit tests)
- Integration scenarios (integration tests)
- Edge cases and error handling

### Run GitHub Actions Workflow

The solution includes a complete GitHub Actions workflow that:

1. **Runs on push/PR**: Automatically validates on code changes
2. **Runs unit tests**: 22 comprehensive tests via `npm test`
3. **Validates matrices**: 6 harness tests via `test/harness.js`
4. **Generates examples**: Demonstrates real-world usage

### Test via act

Run the workflow locally using `act`:

```bash
# All jobs
act push --rm

# Specific job
act push --rm --job test
act push --rm --job matrix-validation
act push --rm --job generate-example-matrix
```

## Implementation Details

### Cartesian Product Algorithm

The solution uses a cartesian product algorithm to generate all combinations:

1. Starts with the first dimension
2. For each subsequent dimension, multiplies each existing combination by all values in that dimension
3. Results in N₁ × N₂ × N₃ ... combinations

### Include/Exclude Processing

1. **Include**: New configurations are added if they don't already exist in the matrix
2. **Exclude**: Configurations matching all specified fields are removed
3. **Order**: Excludes are applied after includes, allowing fine-grained control

### Size Validation

- Default maximum: 256 combinations
- Checked before returning matrix
- Checked again after includes (in case they exceed limit)
- Throws descriptive error with actual vs. max size

## File Structure

```
├── src/
│   └── index.js           # Main matrix generator (exportable + CLI)
├── test/
│   ├── matrix.test.js     # Unit tests (8 tests)
│   ├── integration.test.js # Integration tests (14 tests)
│   ├── fixtures.js         # Test data fixtures
│   └── harness.js          # GitHub Actions test harness
├── .github/workflows/
│   └── environment-matrix-generator.yml  # CI/CD workflow
├── package.json
├── package-lock.json
└── README.md
```

## GitHub Actions Workflow

The workflow (`.github/workflows/environment-matrix-generator.yml`):

- **Triggers**: push, pull_request, workflow_dispatch
- **Jobs**:
  1. `test`: Runs npm test (22 tests)
  2. `matrix-validation`: Runs test harness (6 tests)
  3. `generate-example-matrix`: Demonstrates real usage
- **Environment**: Ubuntu latest with Node.js 20
- **Validation**: actionlint passes ✅

## Error Handling

The solution gracefully handles:

```javascript
// Matrix size exceeded
Error: Matrix size 1000 exceeds maximum of 256

// Invalid JSON input
Error: Invalid JSON: Unexpected token

// Missing module
Error [ERR_MODULE_NOT_FOUND]: Cannot find module
```

## Examples

### Example 1: Simple 2x2 Matrix

```javascript
const matrix = generateMatrix({
  os: ['ubuntu-latest', 'macos-latest'],
  node_version: ['18', '20']
});
// Generates 4 combinations
```

### Example 2: With Excludes

```javascript
const matrix = generateMatrix({
  os: ['ubuntu-latest', 'macos-latest', 'windows-latest'],
  node_version: ['18', '20']
}, {
  exclude: [
    { os: 'macos-latest', node_version: '18' }
  ]
});
// Generates 5 combinations (one excluded)
```

### Example 3: With Custom Fields

```javascript
const matrix = generateMatrix({
  os: ['ubuntu-latest'],
  node_version: ['18'],
  arch: ['x64', 'arm64']
}, {
  include: [
    { os: 'special', node_version: '19', experimental: true }
  ]
});
// 3D matrix + custom include
```

## Performance

- **22 tests**: ~130ms locally
- **Matrix generation**: O(N₁ × N₂ × ... × Nₖ) where N is array size
- **Include/exclude**: O(m × k) where m is matrix size, k is rules count
- **Default 256 limit**: Prevents runaway large matrices

## Compatibility

- **Node.js**: 18+
- **GitHub Actions**: All runners (ubuntu, macos, windows)
- **actionlint**: Validation passes
- **Docker**: Works in act containers
