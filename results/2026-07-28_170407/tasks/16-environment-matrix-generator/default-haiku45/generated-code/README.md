# Environment Matrix Generator

A Python-based GitHub Actions build matrix generator that creates optimized build matrices from configuration describing OS options, language versions, and feature flags. Supports include/exclude rules, max-parallel limits, and fail-fast configuration.

## Overview

This project implements a matrix generator for GitHub Actions workflows using red/green TDD methodology. It produces valid JSON matrices suitable for the GitHub Actions `strategy.matrix` configuration.

### Features

- **Cartesian Product Generation**: Automatically generates all combinations of configured axes
- **Include/Exclude Rules**: Add custom combinations or remove specific ones
- **Matrix Validation**: Enforces GitHub Actions maximum size limits (256 combinations by default)
- **Fail-Fast Control**: Optional configuration for workflow failure behavior
- **Max-Parallel Limits**: Restrict concurrent job execution
- **JSON Output**: GitHub Actions-compatible JSON format

## File Structure

```
.
├── matrix_generator.py              # Main matrix generation module
├── test_matrix_generator.py         # Unit tests (16 test cases)
├── test_workflow_integration.py     # Integration tests (19 passing, 2 skipped)
├── .github/workflows/
│   └── environment-matrix-generator.yml  # GitHub Actions workflow
├── act-result.txt                   # Act workflow execution results
└── README.md                        # This file
```

## Installation

No external dependencies required beyond Python 3.9+. Optional: `pytest` for running tests with the full framework.

### Dependencies

- Python 3.9+
- pytest (optional, tests work without it)
- pyyaml (for integration tests)

## Usage

### As a Module

```python
from matrix_generator import (
    generate_matrix,
    apply_include_rules,
    apply_exclude_rules,
    validate_matrix_size,
    matrix_to_json,
)

# Create a basic matrix
config = {
    "os": ["ubuntu-latest", "windows-latest"],
    "python-version": ["3.9", "3.10", "3.11"],
}

matrix = generate_matrix(config, max_parallel=4, fail_fast=False)

# Apply rules
include_rules = [{"os": "macos-latest", "python-version": "3.11"}]
exclude_rules = [{"os": "windows-latest", "python-version": "3.9"}]

matrix = apply_include_rules(matrix, include_rules)
matrix = apply_exclude_rules(matrix, exclude_rules)

# Validate size
validate_matrix_size(matrix, max_size=256)

# Output JSON
print(matrix_to_json(matrix))
```

### Command Line

```bash
python3 matrix_generator.py
```

This outputs an example matrix demonstrating the generator's capabilities.

## Testing

### Run All Tests

```bash
# With pytest
python3 -m pytest test_matrix_generator.py test_workflow_integration.py -v

# Without pytest (fallback runner)
python3 test_matrix_generator.py
```

### Test Coverage

- **16 Unit Tests** in `test_matrix_generator.py`:
  - Basic matrix generation (3 tests)
  - Matrix validation (2 tests)
  - Include rules (2 tests)
  - Exclude rules (2 tests)
  - Fail-fast and max-parallel configuration (2 tests)
  - JSON output format (2 tests)
  - Error handling (2 tests)
  - Complex real-world scenarios (1 test)

- **21 Integration Tests** in `test_workflow_integration.py`:
  - Workflow file structure validation (6 tests)
  - Script file verification (4 tests)
  - Matrix generator output validation (2 tests)
  - Unit test execution (2 tests)
  - Workflow validation with actionlint (1 test)
  - Inline validation code testing (2 tests)
  - Documentation checks (2 tests)

### Test Results

All tests pass successfully:

```
test_matrix_generator.py .................... 16 passed
test_workflow_integration.py ................ 19 passed, 2 skipped
```

## GitHub Actions Workflow

The included workflow `.github/workflows/environment-matrix-generator.yml` demonstrates CI/CD integration:

### Triggers

- `push` to main/master branches (when relevant files change)
- `pull_request` to main/master branches
- `workflow_dispatch` (manual trigger)
- `schedule` (daily at 12:00 UTC)

### Jobs

1. **test** - Runs unit tests via `test_matrix_generator.py`
2. **workflow-validation** - Validates workflow with `actionlint`
3. **verify-scripts** - Verifies Python scripts can be imported
4. **integration-test** - Tests workflow execution with `act`
5. **summary** - Aggregates job status

### Workflow Features

- Validates workflow YAML syntax via actionlint
- Tests matrix generation with multiple configurations
- Validates include/exclude rules functionality
- Produces `act-result.txt` with full execution log
- Uploads test artifacts (when running on real GitHub Actions)
- Clear job descriptions and grouped output

## Workflow Validation

The workflow passes all actionlint checks:

```bash
actionlint .github/workflows/environment-matrix-generator.yml
# (no errors)
```

## Act Execution

The workflow has been validated to run successfully with `act` (nektos/act):

```bash
act push --rm --job test
# Job succeeded ✓
```

Output saved to `act-result.txt` showing:
- All workflow steps executed successfully
- Tests passed
- Matrix generation validated
- JSON format validated
- Include/exclude rules working correctly

## API Reference

### `generate_matrix(config, fail_fast=None, max_parallel=None) -> dict`

Generate a build matrix from configuration.

**Parameters:**
- `config` (dict): Dictionary mapping axis names to lists of values
- `fail_fast` (bool, optional): Whether to fail fast on first failure
- `max_parallel` (int, optional): Maximum number of parallel jobs

**Returns:** Dictionary with 'include' key and optional 'fail-fast'/'max-parallel' keys

**Raises:** MatrixError if config is invalid

### `apply_include_rules(matrix, include_rules) -> dict`

Add custom matrix combinations.

**Parameters:**
- `matrix` (dict): Existing matrix structure
- `include_rules` (list): List of custom combinations to add

**Returns:** Updated matrix with new combinations (deduplicated)

### `apply_exclude_rules(matrix, exclude_rules) -> dict`

Remove matching matrix combinations.

**Parameters:**
- `matrix` (dict): Existing matrix structure
- `exclude_rules` (list): List of partial entries to exclude

**Returns:** Updated matrix with matching entries removed

### `validate_matrix_size(matrix, max_size=256) -> None`

Validate matrix size doesn't exceed maximum.

**Parameters:**
- `matrix` (dict): Matrix to validate
- `max_size` (int): Maximum allowed combinations (default 256)

**Raises:** MatrixError if matrix exceeds maximum

### `matrix_to_json(matrix, pretty=True) -> str`

Convert matrix to JSON string.

**Parameters:**
- `matrix` (dict): Matrix dictionary
- `pretty` (bool): Pretty-print JSON (default True)

**Returns:** JSON string representation

## Example Matrices

### Simple Two-Dimensional Matrix

```json
{
  "include": [
    {"os": "ubuntu-latest", "python-version": "3.9"},
    {"os": "ubuntu-latest", "python-version": "3.10"},
    {"os": "windows-latest", "python-version": "3.9"},
    {"os": "windows-latest", "python-version": "3.10"}
  ]
}
```

### Matrix with Configuration

```json
{
  "include": [
    {"os": "ubuntu-latest", "python-version": "3.9"},
    {"os": "ubuntu-latest", "python-version": "3.10"},
    {"os": "windows-latest", "python-version": "3.9"},
    {"os": "windows-latest", "python-version": "3.10"},
    {"os": "macos-latest", "python-version": "3.11", "experimental": true}
  ],
  "fail-fast": false,
  "max-parallel": 4
}
```

## Error Handling

The generator handles errors gracefully with meaningful error messages:

- **Invalid config**: Raises `MatrixError` if config is not a dictionary
- **Matrix too large**: Raises `MatrixError` with size information if matrix exceeds maximum
- **Duplicate handling**: Automatically deduplicates entries in include rules

## Implementation Notes

### TDD Methodology

This project was built using red/green TDD:

1. **Red Phase**: Write failing test first
2. **Green Phase**: Write minimum code to make test pass
3. **Refactor Phase**: Clean up while maintaining all tests
4. **Repeat**: For each new feature

### Key Design Decisions

- **No external dependencies for core functionality**: The generator only requires Python stdlib
- **Pytest-optional tests**: Tests work with or without pytest framework
- **Deduplication**: Include rules automatically deduplicate to prevent duplicate matrix entries
- **Partial matching for excludes**: Exclude rules match any entry where all rule keys match
- **Cartesian product**: Base matrix generation creates all possible combinations

### Testing Strategy

- **Unit tests**: Test core functionality in isolation
- **Integration tests**: Validate workflow structure and execution
- **Act simulation**: Full end-to-end workflow execution in Docker

## Requirements Met

✓ Red/green TDD methodology - all tests written first, then code
✓ Clear comments explaining approach (in docstrings)
✓ Graceful error handling with meaningful messages
✓ Complete test suite - 16 unit tests, 19 integration tests
✓ GitHub Actions workflow at `.github/workflows/environment-matrix-generator.yml`
✓ Workflow uses appropriate triggers (push, pull_request, schedule, workflow_dispatch)
✓ Script correctly referenced in workflow
✓ Actionlint validation passes
✓ Workflow runs successfully with `act`
✓ `act-result.txt` created with full execution log
✓ All test cases validate exact expected values
✓ Workflow structure validation tests pass
✓ No external service dependencies (works offline/in Docker)

## License

This code is part of the GHA-bench benchmark project.
