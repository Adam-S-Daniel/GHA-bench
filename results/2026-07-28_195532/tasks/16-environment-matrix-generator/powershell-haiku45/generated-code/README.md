# Environment Matrix Generator

A PowerShell-based tool for generating GitHub Actions build matrices from configuration. Supports dynamic combination generation with include/exclude rules, feature flags, and validation.

## Features

- **Dynamic Matrix Generation**: Creates Cartesian products of OS, language versions, and feature flags
- **Include Rules**: Add specific combinations beyond the base matrix
- **Exclude Rules**: Remove combinations from the generated matrix
- **Feature Flags**: Include feature flags in combinations
- **Max Parallel Limit**: Set GitHub Actions `max-parallel` strategy setting
- **Fail-Fast Configuration**: Control job failure behavior
- **Matrix Size Validation**: Prevent oversized matrices with configurable limits
- **JSON Output**: Output matrix as JSON or PowerShell object

## Usage

### Basic Matrix

```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest")
    language = @("3.10", "3.11")
}

$matrix = New-EnvironmentMatrix -Config $config
$json = $matrix | ConvertTo-Json -Depth 10
```

### With Options

```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest", "macos-latest")
    language = @("3.9", "3.10", "3.11")
    features = @("experimental", "debug")
    maxParallel = 8
    failFast = $true
    maxSize = 100
}

$matrix = New-EnvironmentMatrix -Config $config -AsJson
```

### With Include/Exclude Rules

```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest")
    language = @("3.10")
    include = @(
        @{ os = "macos-latest"; language = "3.9" }
    )
    exclude = @(
        @{ os = "windows-latest"; language = "3.10" }
    )
}

$matrix = New-EnvironmentMatrix -Config $config
```

## Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `os` | Array | No | Operating system options |
| `language` | Array | No | Language/version options (at least one of `os` or `language` required) |
| `features` | Array | No | Feature flags to include in all base combinations |
| `include` | Array | No | Additional combinations to add (each as hashtable) |
| `exclude` | Array | No | Combinations to remove (each as hashtable with matching fields) |
| `maxParallel` | Integer | No | Maximum parallel jobs in GitHub Actions |
| `failFast` | Boolean | No | Fail fast strategy setting |
| `maxSize` | Integer | No | Maximum matrix size (default: 256) |

## Output Structure

The function returns a hashtable matching GitHub Actions matrix format:

```json
{
  "include": [
    { "os": "ubuntu-latest", "language": "3.10", "features": "flag1,flag2" },
    { "os": "windows-latest", "language": "3.11" }
  ],
  "max-parallel": 4,
  "fail-fast": true
}
```

## Error Handling

- Throws error if neither `os` nor `language` specified
- Throws error if matrix size exceeds configured `maxSize`
- Returns empty `include` array if all combinations are excluded

## Testing

Run the test suite with Pester:

```bash
Invoke-Pester Tests/New-EnvironmentMatrix.Tests.ps1 -PassThru
```

The test suite includes:
- Basic matrix generation (2×2, 3×3 combinations)
- Include and exclude rule validation
- Feature flag handling
- Max parallel and fail-fast settings
- Matrix size validation
- JSON output format validation
- Edge cases (empty config, single dimensions, exclude-all)

## GitHub Actions Workflow

The included workflow (`.github/workflows/environment-matrix-generator.yml`) demonstrates:

1. **Test Job**: Runs Pester unit tests on all test cases
2. **Integration Job**: Tests real-world matrix generation scenarios
   - Basic 2×2 matrix generation
   - JSON output validation
   - Include/exclude rule handling
   - Settings validation (max-parallel, fail-fast)
   - Matrix size limits
   - Feature flag inclusion

### Running Locally with act

```bash
act push --rm -W .github/workflows/environment-matrix-generator.yml
```

## Implementation Notes

### Design Approach

The implementation uses a TDD (Test-Driven Development) methodology:
1. Red: Write failing tests first
2. Green: Implement minimum code to pass tests
3. Refactor: Clean up and optimize

### Matrix Generation Algorithm

1. **Base Matrix**: Creates Cartesian product of OS × language versions
   - If only OS: one combination per OS
   - If only language: one combination per language
   - If both: all combinations of both

2. **Include Phase**: Adds explicit combinations from `include` array
   - Preserves existing feature flags unless overridden

3. **Exclude Phase**: Removes combinations matching exclude patterns
   - Matches combinations where ALL specified fields match the pattern
   - Partial matches still exclude (e.g., matching only `os` excludes all languages for that OS)

4. **Validation**: Checks total combinations don't exceed `maxSize`

## Project Structure

```
.
├── src/
│   └── New-EnvironmentMatrix.ps1      Main implementation
├── Tests/
│   └── New-EnvironmentMatrix.Tests.ps1 Test suite (18 test cases)
├── .github/workflows/
│   └── environment-matrix-generator.yml CI/CD workflow
└── README.md                            This file
```

## Test Coverage

18 comprehensive test cases covering:
- Basic matrix generation (2×2, 3×3, larger matrices)
- Include rules (add single or multiple combinations)
- Exclude rules (remove single or multiple combinations)
- Feature flags (basic and custom flags)
- Max parallel enforcement
- Fail-fast configuration
- Matrix size validation (within and exceeding limits)
- JSON output format and structure
- Empty configuration error handling
- Complex scenarios combining all features
- Single-dimension matrices (OS-only, language-only)
- Exclude-all scenarios
- Partial field matching in exclude patterns
- Feature inheritance and override behavior
- Default settings

All tests pass in both local execution and GitHub Actions (via `act`).

## Requirements

- PowerShell 5.1+ or PowerShell Core 7+
- Pester 4.0+ (for testing)
- Docker (for running with `act`)
- actionlint (for workflow validation)

## License

Part of GHA-bench benchmark suite.
