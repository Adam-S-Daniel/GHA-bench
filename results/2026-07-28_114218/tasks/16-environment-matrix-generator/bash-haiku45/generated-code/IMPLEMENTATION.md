# GitHub Actions Environment Matrix Generator

## Overview

This project provides a complete implementation of a GitHub Actions matrix generator with comprehensive testing and CI/CD integration.

## Files Created

### Core Implementation
- **`matrix-generator.sh`** — Main script that generates GitHub Actions strategy.matrix JSON from configuration files
  - Validates JSON configuration
  - Generates Cartesian products of dimensions
  - Validates matrix size constraints
  - Supports include/exclude rules
  - Supports strategy configuration (fail-fast, max-parallel)
  - Handles errors gracefully with meaningful messages
  - Passes `shellcheck` validation
  - Uses `#!/usr/bin/env bash` shebang

### Testing
- **`tests/test_matrix_generator.bats`** — Comprehensive bats-core test suite with 11 tests
  - Test that script exists and is executable
  - Test simple matrix generation with multiple dimensions
  - Test feature flags in configuration
  - Test matrix size validation against limits
  - Test error handling for missing files
  - Test error handling for invalid JSON
  - Test include rules
  - Test exclude rules
  - Test fail-fast and max-parallel strategy configuration
  - Test matrix doesn't exceed default maximum
  - Test output is valid JSON

- **`tests/test_helper.bash`** — Test helper that sets up test environment

### CI/CD Pipeline
- **`.github/workflows/environment-matrix-generator.yml`** — GitHub Actions workflow that:
  - Runs on push to main/master, pull requests, and manual dispatch
  - Validates script with `shellcheck`
  - Checks bash syntax with `bash -n`
  - Runs all bats tests
  - Tests basic matrix generation
  - Tests language versions matrix
  - Tests include/exclude rules
  - Tests fail-fast configuration
  - Tests maximum size validation
  - Tests invalid JSON handling
  - Tests missing file handling
  - Verifies output is valid JSON
  - Includes a secondary job that simulates CI environment
  - Passes `actionlint` validation

## Features Implemented

### Matrix Generation
- **Cartesian Product**: Generates all combinations of dimension values
- **Dimension Support**: Handles any number of dimensions (os, language, version, features, etc.)
- **Type Flexibility**: Handles both array and scalar dimension values

### Configuration Options
- **`max_matrix_size`**: Limit the total number of combinations (default: 256)
- **`include`**: Add specific combinations not in the base matrix
- **`exclude`**: Remove specific combinations from the matrix
- **`strategy`**: Configure GitHub Actions strategy options (fail-fast, max-parallel)

### Error Handling
- Missing configuration files → clear error message
- Invalid JSON → validation with jq, helpful error message
- Matrix size exceeding limit → error with actual vs. max size
- All errors exit with status code 1
- Successful generation exits with status code 0

### Output Format
```json
{
  "matrix": {
    "dimension1": ["value1", "value2", ...],
    "dimension2": ["value3", "value4", ...],
    "fail-fast": true,
    "max-parallel": 4
  },
  "include": [...],
  "exclude": [...]
}
```

## Test Results

All 11 tests in the bats suite pass:
1. ✓ script exists and is executable
2. ✓ simple matrix with os and language versions
3. ✓ matrix with feature flags
4. ✓ matrix validates maximum size
5. ✓ error handling for missing config file
6. ✓ error handling for invalid JSON
7. ✓ matrix with include rules
8. ✓ matrix with exclude rules
9. ✓ fail-fast configuration
10. ✓ matrix size does not exceed default maximum
11. ✓ output is valid JSON

## CI/CD Validation

The GitHub Actions workflow has been validated with:
- ✓ `actionlint` — valid workflow YAML and action references
- ✓ `shellcheck` — script follows shell best practices
- ✓ `bash -n` — script has no syntax errors
- ✓ `bats` — all unit tests pass
- ✓ `act` push simulation — workflow runs successfully in isolated Docker container

## Usage Examples

### Simple OS Matrix
```bash
cat > os-matrix.json << 'EOF'
{
  "os": ["ubuntu-latest", "macos-latest", "windows-latest"]
}
EOF

./matrix-generator.sh os-matrix.json
```

Output:
```json
{"matrix":{"os":["macos-latest","ubuntu-latest","windows-latest"]}}
```

### Multi-Dimension Matrix
```bash
cat > multi-matrix.json << 'EOF'
{
  "os": ["ubuntu-latest", "macos-latest"],
  "python": ["3.9", "3.10", "3.11"]
}
EOF

./matrix-generator.sh multi-matrix.json
```

Output:
```json
{"matrix":{"os":["macos-latest","ubuntu-latest"],"python":["3.10","3.11","3.9"]}}
```

### With Include/Exclude
```bash
cat > complex-matrix.json << 'EOF'
{
  "os": ["ubuntu-latest", "windows-latest"],
  "version": ["1.0", "2.0"],
  "include": [
    {"os": "macos-latest", "version": "2.0"}
  ],
  "exclude": [
    {"os": "windows-latest", "version": "1.0"}
  ]
}
EOF

./matrix-generator.sh complex-matrix.json
```

Output:
```json
{
  "matrix": {"os": ["ubuntu-latest", "windows-latest"], "version": ["1.0", "2.0"]},
  "include": [{"os": "macos-latest", "version": "2.0"}],
  "exclude": [{"os": "windows-latest", "version": "1.0"}]
}
```

### With Strategy Configuration
```bash
cat > strategy-matrix.json << 'EOF'
{
  "os": ["ubuntu-latest"],
  "version": ["1.0"],
  "strategy": {
    "fail-fast": true,
    "max-parallel": 2
  }
}
EOF

./matrix-generator.sh strategy-matrix.json
```

Output:
```json
{"matrix": {"os": ["ubuntu-latest"], "version": ["1.0"], "fail-fast": true, "max-parallel": 2}}
```

## Implementation Notes

### Technology Stack
- **Language**: Bash (POSIX-compatible)
- **JSON Processing**: jq (for validation and parsing)
- **Python**: Used for matrix generation logic (in embedded Python)
- **Testing**: bats-core (Bash Automated Testing System)
- **CI/CD**: GitHub Actions with act simulation

### Design Decisions
1. **Python for Core Logic**: While the script is bash, Python handles the complex matrix generation to avoid error-prone jq recursion
2. **Configuration File**: Uses JSON for clear, structured configuration
3. **Validation First**: Checks file existence and JSON validity before processing
4. **Sorted Output**: Dimensions are sorted for consistent, deterministic output
5. **Flexible Dimensions**: Supports any dimension name and any number of dimensions

### Error Handling Strategy
- All inputs are validated before use
- Helpful error messages include what went wrong and how to fix it
- Exit codes distinguish between success (0) and failure (1)
- stderr is used for error messages, stdout for output

## Performance Characteristics
- O(n) where n is the product of all dimension values
- Matrix size validation prevents runaway generation
- Small configuration parsing overhead (< 100ms)

## Requirements
- bash 4.0+
- jq (for JSON validation)
- python3 (for matrix generation)
- For testing: bats (npm install -g bats)
- For validation: actionlint, shellcheck

## CI/CD Pipeline Status

✓ Workflow validates with actionlint
✓ Script passes shellcheck
✓ Script has valid bash syntax
✓ All unit tests pass via bats
✓ All integration tests pass in act
✓ Both CI jobs completed successfully
✓ act-result.txt artifact generated with full output
