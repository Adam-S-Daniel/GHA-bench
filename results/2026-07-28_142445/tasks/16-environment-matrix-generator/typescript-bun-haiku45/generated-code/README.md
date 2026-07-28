# Environment Matrix Generator

A TypeScript/Bun implementation of a GitHub Actions build matrix generator with support for complex configuration, include/exclude rules, parallel limits, and size validation.

## Features

- **Matrix Generation**: Creates all combinations of OS, language versions, and custom options
- **Include Rules**: Add specific combinations to the matrix
- **Exclude Rules**: Remove unwanted combinations from the matrix
- **Parallel Control**: Set `max-parallel` to limit concurrent job execution
- **Fail-Fast**: Configure whether a single job failure stops the entire build
- **Size Validation**: Ensure matrix doesn't exceed maximum allowed size
- **CLI Interface**: Command-line tool to generate matrices from JSON config
- **GitHub Actions Integration**: Ready-to-use workflow for CI/CD pipelines

## Project Structure

```
.
├── matrix.ts                    # Core matrix generation logic
├── cli.ts                       # CLI interface
├── matrix.test.ts               # Unit tests (16 tests)
├── integration.test.ts          # Integration tests (6 tests)
├── test-runner.sh               # Local test harness
├── .github/workflows/           # GitHub Actions workflow
│   └── environment-matrix-generator.yml
├── fixtures/                    # Test configuration files
│   ├── basic-config.json
│   ├── complex-config.json
│   ├── with-options.json
│   └── advanced-options.json
└── README.md                    # This file
```

## Installation & Usage

### Prerequisites

- Bun 1.0+
- actionlint (for workflow validation)
- Docker (for running workflow with act)

### Run Tests Locally

```bash
# Run all unit tests
bun test matrix.test.ts

# Run integration tests
bun test matrix.test.ts integration.test.ts

# Run complete test suite
./test-runner.sh
```

### CLI Usage

```bash
# Generate matrix from config
bun run cli.ts fixtures/basic-config.json

# Generate matrix with options
bun run cli.ts fixtures/basic-config.json fixtures/with-options.json
```

### Example Configuration

**basic-config.json**:
```json
{
  "os": ["ubuntu-latest", "windows-latest"],
  "nodeVersion": ["18", "20"]
}
```

Output:
```json
{
  "include": [
    { "os": "ubuntu-latest", "nodeVersion": "18" },
    { "os": "ubuntu-latest", "nodeVersion": "20" },
    { "os": "windows-latest", "nodeVersion": "18" },
    { "os": "windows-latest", "nodeVersion": "20" }
  ]
}
```

### Example Options

**with-options.json**:
```json
{
  "exclude": [
    { "os": "windows-latest", "nodeVersion": "18" }
  ],
  "maxParallel": 4,
  "failFast": false
}
```

## API Reference

### `MatrixConfig`

```typescript
interface MatrixConfig {
  os?: string[];
  nodeVersion?: string[];
  pythonVersion?: string[];
  features?: string[];
  [key: string]: string[] | undefined;
}
```

### `MatrixOptions`

```typescript
interface MatrixOptions {
  include?: Array<Record<string, string>>;
  exclude?: Array<Record<string, string>>;
  maxParallel?: number;
  failFast?: boolean;
  maxSize?: number;
}
```

### `generateMatrix(config, options?)`

Generates a GitHub Actions strategy matrix from configuration.

**Returns**: `MatrixStrategy` object with:
- `include`: Array of generated combinations
- `exclude?`: Array of excluded combinations
- `max-parallel?`: Maximum parallel jobs
- `fail-fast?`: Fail fast configuration

## Testing

### Unit Tests (16 tests)

- Basic matrix generation from config
- Cartesian product of all combinations
- Exclude rules
- Include rules
- Max-parallel configuration
- Fail-fast configuration
- Size validation
- Empty config handling
- Multi-dimensional matrices
- Custom configuration keys

### Integration Tests (6 tests)

- Fixture file loading
- JSON parsing and validation
- File existence verification

### Workflow Tests via act

- Unit test execution
- CLI functionality with various fixtures
- Workflow structure validation
- YAML syntax validation with actionlint

## GitHub Actions Workflow

The workflow (`environment-matrix-generator.yml`) includes:

**Triggers**:
- Push to main/master
- Pull requests
- Scheduled runs (daily)
- Manual dispatch

**Steps**:
1. Checkout code
2. Setup Bun runtime
3. Run unit tests
4. Generate matrix from fixtures
5. Validate matrix output
6. Display test results

**Validation**: All steps must pass for workflow to succeed.

## Implementation Details

### Cartesian Product

The core algorithm generates all combinations of input values using cartesian product:

```typescript
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
```

### Size Validation

Matrix size is validated before returning:

```typescript
if (include.length > maxSize) {
  throw new Error(
    `Matrix size (${include.length}) exceeds maximum allowed size (${maxSize})`
  );
}
```

Default `maxSize` is 256 (GitHub Actions limit).

## Error Handling

- **Invalid config**: Returns empty matrix
- **Exceeds max size**: Throws error with details
- **Invalid JSON**: CLI exits with error message
- **Missing files**: CLI reports file not found

## Performance

- Matrix generation: < 50ms for typical configs
- Test suite: 22 tests in ~37ms
- Workflow execution: ~1s for all steps

## Design Decisions

1. **TypeScript**: Strict type safety for configuration validation
2. **TDD Approach**: 16 unit tests + 6 integration tests ensure correctness
3. **Minimal Dependencies**: Only Bun stdlib (fs) for file operations
4. **Explicit Cartesian Product**: Recursive algorithm is clear and maintainable
5. **Flexible Configuration**: Supports arbitrary key-value pairs, not just predefined options
6. **Size Validation**: Prevents runaway matrices that could overwhelm CI

## Limitations

- Maximum matrix size: 256 (configurable)
- All values must be strings
- No regex patterns or conditional logic in config
- Requires explicit include/exclude rules for complex scenarios

## Future Enhancements

- Support for numeric values
- Pattern matching for includes/excludes
- Conditional matrix generation based on triggers
- Import/export matrix between workflows
- Matrix visualization dashboard
