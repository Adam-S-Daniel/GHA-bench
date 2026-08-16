# Environment Matrix Generator

A bash script that generates GitHub Actions build matrices from configuration, with support for include/exclude rules, max-parallel limits, and fail-fast configuration.

## Features

- **Cartesian Product Generation**: Automatically generates all combinations of matrix dimensions (os, node versions, etc.)
- **Include/Exclude Rules**: Support for custom include and exclude rules to fine-tune matrix combinations
- **Configuration Options**:
  - `max-parallel`: Limit parallel job execution
  - `fail-fast`: Control whether to fail fast on first failure (default: true)
  - `max-size`: Validate matrix doesn't exceed maximum size (default: 256)
- **Error Handling**: Validates matrix size and reports meaningful errors
- **JSON Output**: Generates valid GitHub Actions strategy.matrix JSON

## Usage

```bash
# Simple matrix
echo '{"os": ["ubuntu-latest"], "node": ["20"]}' | ./matrix-generator.sh

# Complex matrix with all options
cat <<EOF | ./matrix-generator.sh
{
  "os": ["ubuntu-latest", "macos-latest", "windows-latest"],
  "node": ["18", "20"],
  "max-parallel": 4,
  "fail-fast": false,
  "include": [{"os": "ubuntu-latest", "node": "22", "experimental": true}],
  "exclude": [{"os": "windows-latest", "node": "18"}],
  "max-size": 256
}
EOF
```

## Testing

### Local Testing with bats

```bash
# Install bats-core
sudo apt-get install bats

# Run all tests
bats tests/matrix-generator.bats

# Run with GitHub Actions workflow locally
act push
```

### Test Results

- **11 unit tests** covering all features
- **GitHub Actions workflow validation** via actionlint
- **Integration tests** running through act (GitHub Actions local runner)

All tests PASS ✓

## Files

```
.
├── matrix-generator.sh           # Main script
├── tests/
│   └── matrix-generator.bats     # Test suite
├── fixtures/
│   ├── simple.json              # Simple test fixture
│   └── complex.json             # Complex test fixture
├── .github/workflows/
│   └── environment-matrix-generator.yml  # GitHub Actions workflow
├── act-result.txt               # Act test execution results
└── README.md                    # This file
```

## CI/CD

The project includes a GitHub Actions workflow that:
1. Validates script syntax with shellcheck and bash -n
2. Runs bats unit tests
3. Tests basic and complex matrix generation scenarios
4. Tests error handling and edge cases
5. Validates YAML syntax
6. Verifies referenced script files exist

All jobs run successfully when executed via `act` (GitHub Actions local runner).

## Requirements

- bash >= 4.0
- jq for JSON processing
- bats-core (for testing)
- shellcheck (for linting)
- Docker (for running tests via act)

## Exit Codes

- `0`: Successful execution
- `1`: Invalid input or configuration
- `5`: Matrix size validation error

## Examples

### Basic Matrix

Input:
```json
{"os": ["ubuntu-latest"], "node": ["20"]}
```

Output:
```json
{
  "include": [{"os": "ubuntu-latest", "node": "20"}],
  "exclude": [],
  "fail-fast": true
}
```

### Matrix with Exclusions

Input:
```json
{
  "os": ["ubuntu-latest", "macos-latest"],
  "node": ["18", "20"],
  "exclude": [{"os": "macos-latest", "node": "18"}]
}
```

Output:
```json
{
  "include": [
    {"os": "ubuntu-latest", "node": "18"},
    {"os": "ubuntu-latest", "node": "20"},
    {"os": "macos-latest", "node": "20"}
  ],
  "exclude": [{"os": "macos-latest", "node": "18"}],
  "fail-fast": true
}
```

## Implementation Notes

- Uses pure jq for all JSON manipulation to avoid bash variable expansion issues with booleans
- Properly handles boolean `false` values using `has()` instead of `//` operator
- All arrays are optional - empty arrays default to `[]`
- fail-fast defaults to `true` when not specified
