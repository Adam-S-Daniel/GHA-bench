# Environment Matrix Generator

A TypeScript + Bun application for generating GitHub Actions build matrices from configuration. Supports include/exclude rules, max-parallel limits, and fail-fast configuration.

## Features

- **Cartesian Product Generation**: Automatically generates all combinations from specified dimensions (OS, versions, features)
- **Include/Exclude Rules**: Fine-tune matrix with explicit include and exclude patterns
- **Strategy Configuration**: Set fail-fast and max-parallel limits
- **Size Validation**: Prevent generating matrices that exceed specified limits
- **Type-Safe**: Full TypeScript support with explicit type definitions
- **Flexible Dimensions**: Support for standard (os, nodeVersion, pythonVersion) and custom dimensions

## Project Structure

```
.
├── src/
│   ├── generator.ts          # Main matrix generator implementation
│   ├── matrix.test.ts        # Basic functionality tests
│   └── advanced.test.ts      # Advanced scenario tests
├── fixtures/
│   ├── basic.json            # Simple 2x2 matrix fixture
│   ├── with-excludes.json    # Matrix with exclusion rules
│   └── complex.json          # Matrix with features and custom includes
├── .github/
│   └── workflows/
│       └── environment-matrix-generator.yml  # GitHub Actions workflow
├── package.json              # Bun configuration
├── tsconfig.json             # TypeScript configuration
├── test-workflow.sh          # Workflow validation script
└── act-result.txt            # GitHub Actions test results
```

## Installation & Usage

### Local Development

```bash
# Install dependencies
bun install

# Run all tests
bun test

# Generate matrix from fixture
bun run src/generator.ts fixtures/basic.json

# Run generator CLI
bun run src/generator.ts <config.json>
```

### Input Configuration

Create a JSON configuration file describing your matrix:

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "nodeVersion": ["18", "20"],
  "features": {
    "experimental": [true, false]
  },
  "exclude": [
    { "os": "macos-latest", "nodeVersion": "18" }
  ],
  "failFast": false,
  "maxParallel": 4,
  "maxSize": 256
}
```

### Output

The generator produces JSON suitable for `strategy.matrix` in GitHub Actions:

```json
{
  "matrix": {
    "include": [
      { "os": "ubuntu-latest", "nodeVersion": "18", "experimental": true },
      { "os": "ubuntu-latest", "nodeVersion": "18", "experimental": false },
      ...
    ],
    "exclude": [
      { "os": "macos-latest", "nodeVersion": "18" }
    ]
  },
  "strategy": {
    "fail-fast": false,
    "max-parallel": 4
  }
}
```

## Configuration Reference

### Dimensions

Standard dimensions (automatically included if provided):
- `os`: Array of operating systems (e.g., "ubuntu-latest", "windows-latest")
- `nodeVersion`: Array of Node.js versions
- `pythonVersion`: Array of Python versions
- `rubyVersion`: Array of Ruby versions
- `features`: Object with feature flags as boolean/string arrays

Custom dimensions can be added as top-level arrays.

### Rules

- `include`: Array of custom matrix entries to add beyond cartesian product
- `exclude`: Array of patterns to exclude from generated combinations
- `failFast`: Boolean - whether to cancel other jobs if one fails (default: true if not specified)
- `maxParallel`: Maximum number of concurrent jobs
- `maxSize`: Maximum number of matrix combinations (default: 256)

## Testing

### Unit Tests

```bash
bun test
```

Runs 28 tests covering:
- Basic cartesian product generation
- Include/exclude rule application
- Feature flag handling
- Strategy configuration
- Matrix size validation
- Error handling for invalid configurations
- Real-world scenario testing

### Workflow Tests

The GitHub Actions workflow (`environment-matrix-generator.yml`) automatically:
1. Runs all unit tests via `bun test`
2. Generates matrices from test fixtures
3. Validates output JSON structure and content
4. Tests error handling with invalid inputs
5. Validates workflow structure and actionlint compliance

Run workflow locally with:
```bash
act push
```

## Examples

### Basic 2x2 Matrix

```bash
bun run src/generator.ts fixtures/basic.json
```

Generates 4 combinations (2 OS × 2 Node versions).

### Matrix with Exclusions

```bash
bun run src/generator.ts fixtures/with-excludes.json
```

Generates 9 base combinations (3 OS × 3 versions) minus 2 explicit excludes = 7 total.

### Complex Matrix with Features

```bash
bun run src/generator.ts fixtures/complex.json
```

Combines dimensions with feature flags and custom includes.

## GitHub Actions Integration

Use the generated matrix directly in your workflow:

```yaml
name: Test Matrix

on: [push, pull_request]

jobs:
  generate-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.gen.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
      - id: gen
        run: echo "matrix=$(bun run src/generator.ts config.json | jq -c .matrix)" >> $GITHUB_OUTPUT

  test:
    needs: generate-matrix
    strategy:
      matrix: ${{ fromJSON(needs.generate-matrix.outputs.matrix) }}
      fail-fast: false
      max-parallel: 4
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
      - run: echo "Testing on ${{ matrix.os }} with Node ${{ matrix.nodeVersion }}"
```

## Implementation Notes

### TDD Approach

This project was built using red/green TDD:
1. Write failing tests first
2. Implement minimum code to pass tests
3. Refactor and iterate
4. Add more comprehensive tests
5. Validate through GitHub Actions workflow

### Key Design Decisions

- **Cartesian Product**: All dimension combinations are generated unless explicitly excluded
- **Flexible Dimensions**: Not limited to predefined OS/version fields - supports any JSON keys
- **Validation First**: Checks for empty dimensions and size limits before generating
- **Clean JSON Output**: Direct compatibility with GitHub Actions matrix strategy

### Error Handling

The generator validates:
- No empty dimensions (when explicitly specified)
- At least one non-empty dimension in configuration
- Generated matrix size doesn't exceed configured maximum
- Valid JSON output format

## CI/CD Status

✅ All 28 unit tests passing  
✅ GitHub Actions workflow validated with actionlint  
✅ Complete workflow execution successful via `act`  
✅ Test fixtures generate expected output  
✅ Error handling verified with invalid inputs  

See `act-result.txt` for complete workflow execution results.
