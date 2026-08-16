# Environment Matrix Generator

A GitHub Actions matrix generator that converts configuration into build matrix JSON suitable for `strategy.matrix`.

## Features

- **Product Generation**: Automatically generates matrix as Cartesian product of OS, language versions, and feature flags
- **Include/Exclude Rules**: Support for explicit include lists and exclude rule filtering
- **Configuration Options**: Fail-fast mode, max-parallel limits, and matrix size validation
- **Error Handling**: Graceful error messages for invalid configurations and size violations
- **TDD Methodology**: Comprehensive test suite with 100% pass rate

## Solution Architecture

### Core Components

1. **MatrixGenerator** (`src/generator.js`)
   - Main class for generating build matrices
   - Supports two modes:
     - **Product mode**: Generates combinations from array dimensions
     - **Include/Exclude mode**: Filters explicit combinations
   - Validates matrix size against maximum limit (default 256)

2. **CLI Tool** (`src/cli.js`)
   - Command-line interface for generating matrices
   - Reads JSON configuration from file
   - Outputs generated matrix to JSON file and stdout

3. **Test Suite** (`tests/test-runner.js`)
   - 10 comprehensive test cases covering all functionality
   - Custom test harness (no external dependencies)
   - Tests:
     - Basic matrix generation from include lists
     - Product generation from dimension arrays
     - Exclude rule filtering
     - Fail-fast and max-parallel configuration
     - Matrix size validation
     - Feature flag support
     - Multi-dimensional products

4. **GitHub Actions Workflow** (`.github/workflows/environment-matrix-generator.yml`)
   - Runs on push, pull_request, and workflow_dispatch
   - Executes all tests via `npm test`
   - Tests CLI with three fixture scenarios:
     - Basic 2D matrix (OS × Node versions)
     - 3D matrix with excludes and configuration
     - Matrix with feature flags
   - Validates all outputs match expected results
   - Includes actionlint validation

## Usage

### As a Node.js Module

```javascript
import { MatrixGenerator } from './src/generator.js';

const config = {
  os: ['ubuntu-latest', 'windows-latest'],
  node: ['18', '20'],
  exclude: [
    { os: 'windows-latest', node: '18' }
  ],
  failFast: true,
  maxParallel: 4
};

const generator = new MatrixGenerator();
const matrix = generator.generate(config);

console.log(JSON.stringify(matrix, null, 2));
// Output:
// {
//   "include": [
//     { "os": "ubuntu-latest", "node": "18" },
//     { "os": "ubuntu-latest", "node": "20" },
//     { "os": "windows-latest", "node": "20" }
//   ],
//   "failFast": true,
//   "maxParallel": 4
// }
```

### Via CLI

```bash
# Create configuration file
cat > matrix-config.json << EOF
{
  "os": ["ubuntu-latest", "windows-latest"],
  "node": ["18", "20"],
  "failFast": true
}
EOF

# Generate matrix
node src/cli.js matrix-config.json output.json

# Use in GitHub Actions
matrix=$(cat output.json)
echo "matrix=${matrix}" >> $GITHUB_OUTPUT
```

### In GitHub Actions Workflow

```yaml
- name: Generate Build Matrix
  run: node src/cli.js matrix-config.json matrix.json

- name: Use Matrix
  uses: some-action@v1
  with:
    matrix: ${{ fromJson(steps.generate.outputs.matrix) }}
```

## Configuration Format

### Basic Example (Product Mode)

```json
{
  "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
  "node": ["16", "18", "20"],
  "features": ["minimal", "full"]
}
```

Generates 3 × 3 × 2 = 18 combinations automatically.

### Advanced Example (Include/Exclude Mode)

```json
{
  "include": [
    { "os": "ubuntu-latest", "node": "18" },
    { "os": "ubuntu-latest", "node": "20" },
    { "os": "windows-latest", "node": "18" },
    { "os": "windows-latest", "node": "20" }
  ],
  "exclude": [
    { "os": "windows-latest", "node": "18" }
  ],
  "failFast": true,
  "maxParallel": 4,
  "maxSize": 100
}
```

### Configuration Properties

- **Dimension Arrays** (os, node, features, etc.): Array of values for that dimension
  - Used in product mode
  - Creates Cartesian product of all dimensions
  - Multiple dimensions supported (no hardcoded limit)

- **include**: Explicit list of matrix combinations
  - If provided, overrides dimension-based generation
  - Each entry is an object with dimension keys/values

- **exclude**: Array of combinations to remove from matrix
  - Works with both modes
  - Each entry matches if all specified keys match

- **failFast**: Boolean (optional)
  - When true, stops all jobs if any job fails

- **maxParallel**: Number (optional)
  - Maximum number of jobs to run in parallel

- **maxSize**: Number (optional, default 256)
  - Validates matrix doesn't exceed this size
  - Throws error if exceeded

## Test Results

All 10 tests pass successfully:

```
✅ should generate basic matrix from config
✅ should generate matrix from product of OS and versions
✅ should exclude specified combinations
✅ should include fail-fast configuration
✅ should include max-parallel configuration
✅ should validate matrix size against maximum
✅ should support feature flags in matrix
✅ should handle include and exclude together
✅ should handle empty include list
✅ should generate product with three dimensions
```

### Test Fixtures

The solution includes three test fixtures demonstrating various capabilities:

1. **Fixture 1**: Basic 2D product matrix (4 combinations)
2. **Fixture 2**: 3D product with excludes and configuration (5 combinations)
3. **Fixture 3**: Feature flags in matrix (4 combinations)

## Workflow Validation

- ✅ actionlint passes cleanly
- ✅ Valid YAML syntax
- ✅ Correct action references
- ✅ Proper trigger configuration
- ✅ All steps execute successfully via act

## Running Tests

### Unit Tests Only

```bash
npm test
```

### Via GitHub Actions (act)

```bash
act push --rm
```

Runs complete workflow including:
- Unit tests
- CLI tests with fixtures
- Output verification
- Workflow validation

## Implementation Approach

### TDD Methodology

1. **Write Failing Test**: Created comprehensive test suite covering all features
2. **Implement Minimum Code**: Added MatrixGenerator class to pass tests
3. **Refactor**: Cleaned up code, added error handling
4. **Repeat**: Each feature was test-driven

### Code Quality

- **No External Dependencies**: Uses only Node.js built-ins
- **Clear Comments**: Explains approach and key algorithms
- **Error Messages**: Meaningful errors for invalid input
- **Graceful Handling**: Validates input, catches edge cases

### Performance

- **Efficient Algorithm**: Cartesian product generation O(n₁×n₂×...×nₖ)
- **Size Validation**: Prevents memory issues from oversized matrices
- **Minimal Dependencies**: Fast execution, small footprint

## Edge Cases Handled

- Empty include lists
- Multi-dimensional products (3+ dimensions)
- Partial excludes (exclude rules matching subset of dimensions)
- Maximum size validation and clear error messages
- Missing configuration files with helpful error output
- JSON parsing errors with syntax error indication

## Future Enhancements

Potential improvements (not in current scope):

- Support for conditional matrix entries
- Custom naming strategies for matrix entries
- Matrix size optimization suggestions
- YAML output format support
- Integration with GitHub API for dynamic configuration
