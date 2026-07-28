# Environment Matrix Generator

Generates build matrices for GitHub Actions from configuration describing OS options, language versions, and feature flags.

## Features

- **Cartesian product generation**: Automatically generates all combinations of OS, language versions, and feature flags
- **Include/Exclude rules**: Override or filter matrix combinations with granular control
- **Validation**: Enforce matrix size limits and configuration requirements
- **Strategy configuration**: Support for fail-fast and max-parallel settings
- **JSON I/O**: Accept configuration from JSON input, produce JSON suitable for GitHub Actions

## Installation

```bash
python3 -m pip install pytest  # For running pytest tests
```

## Usage

### Command Line

```bash
# Basic usage - read config from stdin
python3 generate_matrix.py << 'EOF'
{
  "os_options": ["ubuntu-latest", "macos-latest"],
  "language_versions": {"python": ["3.11", "3.12"]},
  "feature_flags": {"debug": [true, false]}
}
EOF

# Read from file
python3 generate_matrix.py --config config.json

# Include strategy configuration
python3 generate_matrix.py --strategy --config config.json

# Set maximum matrix size
python3 generate_matrix.py --max-size 10 --config config.json
```

### Python Module

```python
from matrix_generator import generate_matrix, validate_matrix, MatrixConfig

# Create configuration
config = MatrixConfig(
    os_options=["ubuntu-latest", "macos-latest"],
    language_versions={"python": ["3.11", "3.12"]},
    feature_flags={"debug": [True, False]},
    exclude=[{"os": "macos-latest", "debug": True}],
    fail_fast=False,
    max_parallel=8,
)

# Generate matrix
matrix = generate_matrix(config)

# Validate matrix
validate_matrix(matrix, max_size=256)

# Output as JSON
import json
print(json.dumps(matrix, indent=2))
```

## Configuration Format

```json
{
  "os_options": ["ubuntu-latest", "macos-latest", "windows-latest"],
  "language_versions": {
    "python": ["3.9", "3.11", "3.12"],
    "node": ["18", "20"]
  },
  "feature_flags": {
    "debug": [true, false],
    "optimization": ["none", "full"]
  },
  "include": [],
  "exclude": [
    {"os": "windows-latest", "python": "3.9"}
  ],
  "fail_fast": false,
  "max_parallel": 256
}
```

### Fields

- **os_options** (required): List of GitHub Actions runner OS names
- **language_versions** (required): Dict of language names to version lists
- **feature_flags** (optional): Dict of flag names to possible values
- **include** (optional): List of specific combinations to include (overrides cartesian product)
- **exclude** (optional): List of combinations to exclude from matrix
- **fail_fast** (optional): Boolean to fail entire matrix on first failure
- **max_parallel** (optional): Maximum number of parallel jobs (default: 256)

## GitHub Actions Example

```yaml
name: Test Matrix

on: [push, pull_request]

jobs:
  generate-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.generate.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - name: Generate matrix
        id: generate
        run: |
          MATRIX=$(python3 generate_matrix.py --config .github/matrix-config.json)
          echo "matrix=$(echo $MATRIX | jq -c .)" >> $GITHUB_OUTPUT

  test:
    needs: generate-matrix
    strategy:
      matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on ${{ matrix.os }} with Python ${{ matrix.python }}"
```

## Testing

### Run Unit Tests

```bash
# Using pytest
python3 -m pytest test_matrix_generator.py -v

# Using standalone runner (no pytest required)
python3 run_tests.py
```

### Run Through GitHub Actions (locally with act)

```bash
# Validate workflow
actionlint .github/workflows/environment-matrix-generator.yml

# Run workflow locally
act push --rm
```

## Test Coverage

- **21 unit tests** covering all functionality
- **12 integration tests** in standalone runner
- **13 workflow steps** validated through act

All tests passing: ✅

## Files

- `matrix_generator.py` - Core matrix generation module
- `generate_matrix.py` - CLI entry point
- `test_matrix_generator.py` - Comprehensive pytest unit tests
- `run_tests.py` - Standalone test runner (no external dependencies)
- `test_fixtures.py` - Reusable test fixtures
- `.github/workflows/environment-matrix-generator.yml` - GitHub Actions workflow
- `act-result.txt` - Test execution output from act

## Example Outputs

### Basic Matrix (1 entry)

```json
[
  {
    "os": "ubuntu-latest",
    "python": "3.11"
  }
]
```

### Multiple OS (4 entries)

```json
[
  {"os": "ubuntu-latest", "python": "3.11"},
  {"os": "ubuntu-latest", "python": "3.12"},
  {"os": "macos-latest", "python": "3.11"},
  {"os": "macos-latest", "python": "3.12"}
]
```

### With Exclude Rules (3 entries from 4)

```json
[
  {"os": "ubuntu-latest", "python": "3.11"},
  {"os": "ubuntu-latest", "python": "3.12"},
  {"os": "macos-latest", "python": "3.12"}
]
```

### With Strategy Config

```json
{
  "strategy": {
    "fail-fast": false,
    "max-parallel": 4
  },
  "matrix": [
    {"os": "ubuntu-latest", "python": "3.11"}
  ]
}
```

## Error Handling

The tool provides clear error messages for invalid configurations:

```
Error: At least one OS option is required
Error: At least one language version is required
Error: Matrix size 4 exceeds max_size 1
```

## License

Public domain. Use freely in your projects.
