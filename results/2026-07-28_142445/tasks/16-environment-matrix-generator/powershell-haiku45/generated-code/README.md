# Environment Matrix Generator for GitHub Actions

A PowerShell solution for generating GitHub Actions build matrices from OS options, language versions, and feature flags. Supports cartesian product generation, include/exclude rules, max-parallel limits, and fail-fast configuration with comprehensive matrix size validation.

## Overview

This project demonstrates test-driven development (TDD) principles by:
1. Writing failing tests first (red phase)
2. Implementing minimal code to pass tests (green phase)
3. Refactoring for clarity and maintainability (refactor phase)

The solution includes:
- **Script**: `src/EnvironmentMatrixGenerator.ps1` - Core matrix generation functions
- **Tests**: `tests/EnvironmentMatrixGenerator.Tests.ps1` - Comprehensive Pester test suite
- **Workflow**: `.github/workflows/environment-matrix-generator.yml` - GitHub Actions CI/CD pipeline
- **Fixtures**: `tests/fixtures/` - Test configuration examples

## Features

### Core Functionality

- **Cartesian Product Generation**: Automatically generates all combinations of matrix dimensions
- **Include Rules**: Add extra job combinations beyond the cartesian product
- **Exclude Rules**: Remove specific combinations from the matrix
- **Size Validation**: Prevent excessively large matrices with configurable limits (default: 256)
- **Max-Parallel**: Control maximum concurrent jobs
- **Fail-Fast**: Configure whether single job failures stop the matrix

### Example Usage

```powershell
# Load the module
. .\src\EnvironmentMatrixGenerator.ps1

# Basic matrix generation
$config = @{
    os           = @("ubuntu-latest", "windows-latest")
    'node-version' = @("18", "20")
}

$result = New-EnvironmentMatrix -Configuration $config
$result | ConvertTo-Json
```

## Project Structure

```
.
├── src/
│   └── EnvironmentMatrixGenerator.ps1   # Main implementation
├── tests/
│   ├── EnvironmentMatrixGenerator.Tests.ps1  # Pester test suite
│   └── fixtures/
│       ├── simple-matrix.json
│       └── matrix-with-rules.json
└── .github/workflows/
    └── environment-matrix-generator.yml  # CI/CD pipeline
```

## Testing

### Running Tests Locally

```powershell
# Run all tests with Pester
Invoke-Pester ./tests/EnvironmentMatrixGenerator.Tests.ps1 -PassThru

# Run with verbose output
Invoke-Pester ./tests/EnvironmentMatrixGenerator.Tests.ps1 -Verbose
```

### Test Coverage

The test suite includes 8 test cases covering:

1. **Basic matrix generation** - Validates cartesian product of dimensions
2. **Include rules** - Verifies additional combinations can be added
3. **Exclude rules** - Confirms specific combinations can be removed
4. **Matrix size validation** - Ensures matrices don't exceed limits
5. **Max-parallel configuration** - Tests parallel job limits
6. **Fail-fast configuration** - Validates fail-fast setting
7. **Output formatting** - Ensures JSON validity
8. **Error handling** - Tests invalid configuration rejection

### CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/environment-matrix-generator.yml`) provides:

- **Automatic Testing**: Runs Pester tests on push, pull request, and scheduled triggers
- **Workflow Validation**: Validates YAML syntax with actionlint
- **Artifact Upload**: Captures test results and logs
- **Status Reporting**: Clear pass/fail indicators with detailed metrics

#### Workflow Triggers

- **push**: On changes to `src/`, `tests/`, or workflow files on main/master/develop
- **pull_request**: On PRs to main/master
- **workflow_dispatch**: Manual trigger from GitHub Actions tab
- **schedule**: Daily at 2:00 UTC

#### Required Permissions

- `contents: read` - Read repository contents for checkout

## Functions

### `New-EnvironmentMatrix`

Generates a GitHub Actions build matrix from configuration.

**Parameters:**
- `Configuration` (hashtable, required): Matrix dimensions and strategy rules
- `MaxMatrixSize` (int, default: 256): Maximum allowed combinations
- `MaxParallel` (int, default: 0): Maximum concurrent jobs
- `FailFast` (switch): Whether to fail all jobs if any fails

**Output:**
- PSCustomObject with `include` array and optional `max-parallel`, `fail-fast`, and metadata

**Example:**
```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest", "macos-latest")
    version = @("18", "20")
    include = @(@{ os = "macos-latest"; version = "20.1" })
    exclude = @(@{ os = "windows-latest"; version = "18" })
}

$result = New-EnvironmentMatrix -Configuration $config -MaxParallel 4 -FailFast:$true
```

### Helper Functions

- `Get-CartesianProduct`: Generates cartesian product of dimensions
- `Test-CombinationMatches`: Tests if combination matches rule

## GitHub Actions Integration

The workflow creates a build matrix suitable for GitHub Actions' `strategy.matrix`:

```yaml
strategy:
  max-parallel: 4
  fail-fast: true
  matrix:
    include:
      - os: ubuntu-latest
        version: '18'
      - os: ubuntu-latest
        version: '20'
      - os: windows-latest
        version: '20'
      - os: macos-latest
        version: '18'
```

## Development Workflow

The implementation follows red-green-refactor TDD:

### Phase 1: Red (Failing Tests)
- Write comprehensive test suite upfront
- Tests fail because implementation doesn't exist
- Validates test quality and coverage

### Phase 2: Green (Minimal Implementation)
- Write minimum code to pass each test
- Focus on correctness over optimization
- Avoid premature abstraction

### Phase 3: Refactor (Improvement)
- Improve code clarity and efficiency
- Maintain all test passes
- Ensure backward compatibility

## Error Handling

The script provides meaningful error messages for:

- **Empty configuration**: "Configuration is empty"
- **No dimensions**: "No matrix dimensions found after removing include/exclude"
- **Oversized matrix**: "Matrix size (N) exceeds maximum (M)"

Invalid configurations return a structured error object:
```powershell
@{
    valid = $false
    error = "Description of error"
    include = @()
}
```

## Performance Notes

- Cartesian product calculation is O(n1 × n2 × ... × nk) where n is dimension size
- Default limit of 256 combinations prevents runaway matrix growth
- Typical execution time: <10ms for matrices under 100 combinations

## Requirements

- PowerShell 6.0+ (pwsh)
- Pester 6.0+ (for testing)
- No external dependencies for core script

## License

This implementation is provided as-is for GitHub Actions matrix generation.
