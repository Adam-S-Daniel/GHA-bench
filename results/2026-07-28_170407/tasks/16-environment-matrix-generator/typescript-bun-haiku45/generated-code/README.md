# Environment Matrix Generator

A TypeScript/Bun-based tool to generate GitHub Actions build matrices from configuration files. Supports include/exclude rules, max-parallel limits, and fail-fast configuration with built-in validation.

## Features

- **Cartesian Product Matrix Generation**: Combines multiple dimensions (OS, Node versions, etc.) into all possible combinations
- **Include/Exclude Rules**: Refine matrix combinations with explicit rules
- **Configuration Options**: Support for `maxParallel` and `failFast` settings
- **Matrix Size Validation**: Prevents oversized matrices (default max: 256 combinations)
- **JSON Output**: Produces valid GitHub Actions `strategy.matrix` JSON
- **CLI Interface**: Command-line tool for generating matrices from config files
- **Comprehensive Tests**: Full test coverage with 13 passing tests

## Installation

```bash
# Clone the repository
git clone <repo-url>
cd environment-matrix-generator

# Install dependencies (if any)
bun install
```

## Usage

### Using the CLI

```bash
# Generate matrix from a config file
bun run cli.ts config.json

# Or pipe JSON to stdin
echo '{"os": ["ubuntu-latest"], "nodeVersion": ["18"]}' | bun run cli.ts
```

### Configuration File Format

```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "nodeVersion": ["18", "20"],
  "python": ["3.9", "3.10"],
  "includeRules": [
    {"os": "ubuntu-latest", "nodeVersion": "18", "python": "3.9"}
  ],
  "excludeRules": [
    {"os": "macos-latest", "nodeVersion": "18"}
  ],
  "maxParallel": 4,
  "failFast": false,
  "maxSize": 256
}
```

### Output Example

```json
{
  "matrix": {
    "include": [
      {"os": "ubuntu-latest", "nodeVersion": "18"},
      {"os": "ubuntu-latest", "nodeVersion": "20"},
      {"os": "macos-latest", "nodeVersion": "18"},
      {"os": "macos-latest", "nodeVersion": "20"}
    ],
    "exclude": [
      {"os": "macos-latest", "nodeVersion": "18"}
    ]
  },
  "maxParallel": 4,
  "failFast": false
}
```

## Testing

Run the full test suite:

```bash
bun test
```

This runs 13 tests covering:
- Basic matrix generation
- Cartesian product combinations
- Exclude rules
- Configuration options (maxParallel, failFast)
- Matrix size validation
- JSON serialization
- Edge cases (empty config, single OS, multiple excludes)

## GitHub Actions Workflow

The project includes a GitHub Actions workflow (``.github/workflows/environment-matrix-generator.yml`) that:

- Runs on push, pull request, and manual trigger
- Sets up Bun runtime
- Runs all unit tests
- Tests matrix generation with various configurations
- Validates matrix size constraints

### Running the Workflow Locally

```bash
# Install nektos/act
# https://github.com/nektos/act

# Run the workflow locally
act push --rm
```

## Workflow Validation

Validate the workflow structure:

```bash
./validate-workflow.sh
```

This checks:
- Workflow YAML syntax
- Required fields presence
- File dependencies
- actionlint compliance

## Architecture

### Core Components

- **matrix.ts**: Core matrix generation logic
  - `generateMatrix(config)`: Generates matrix from configuration
  - `serializeMatrixJSON(result)`: Converts matrix to JSON string
  - Type definitions for `MatrixConfig`, `MatrixEntry`, `MatrixResult`

- **cli.ts**: Command-line interface
  - Reads config from file or stdin
  - Handles errors gracefully
  - Outputs JSON to stdout

- **Tests**: Comprehensive test coverage
  - matrix.test.ts: 12 unit tests for core logic
  - cli.test.ts: 1 integration test

## Configuration Limits

- **Default Matrix Size Limit**: 256 combinations
- **Customizable**: Set `maxSize` in config to override

## Error Handling

The tool provides meaningful error messages:

```
Error: Matrix size 10000 exceeds maximum allowed size 1000
Error: Invalid JSON in config
Error: Config file not found: /path/to/config.json
```

## Development

### Adding New Features

1. Write failing test first (TDD)
2. Implement minimum code to pass test
3. Refactor if needed
4. Update workflow if necessary

### Test Coverage

- Unit tests: `bun test`
- Integration tests: GitHub Actions workflow via `act`
- Workflow validation: `./validate-workflow.sh`

## License

MIT
