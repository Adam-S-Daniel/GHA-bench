# GitHub Actions Environment Matrix Generator

A production-ready PowerShell solution for generating build matrices for GitHub Actions CI/CD pipelines.

## Quick Start

### Run Tests
```bash
Invoke-Pester -Path Test-MatrixGenerator.ps1
```

### Generate a Matrix
```powershell
. ./New-GitHubActionsMatrix.ps1

$config = @{
    os = @("ubuntu-latest", "windows-latest")
    node_version = @("18.x", "20.x")
    exclude = @(
        @{ os = "windows-latest"; node_version = "18.x" }
    )
    max_parallel = 3
}

$matrix = New-GitHubActionsMatrix -Config $config
$matrix | ConvertTo-Json
```

## Features

✅ **Multi-dimensional matrices** - Cartesian product of any number of dimensions  
✅ **Include/Exclude rules** - Fine-grained control over matrix combinations  
✅ **Parallel configuration** - Set max-parallel limits  
✅ **Fail-fast control** - Configure fail-fast behavior  
✅ **Size validation** - Prevent accidentally huge matrices  
✅ **Comprehensive testing** - 12 Pester tests with 100% pass rate  
✅ **GitHub Actions integration** - Production workflow included  
✅ **Error handling** - Meaningful error messages for all failure modes  

## Files

| File | Purpose |
|------|---------|
| `New-GitHubActionsMatrix.ps1` | Core matrix generation engine |
| `Test-MatrixGenerator.ps1` | 12 comprehensive Pester tests |
| `Generate-Matrix.ps1` | GitHub Actions wrapper script |
| `.github/workflows/environment-matrix-generator.yml` | CI/CD workflow |
| `act-result.txt` | Test execution log (act validation) |
| `IMPLEMENTATION.md` | Detailed technical documentation |

## Configuration

### Input Schema
```powershell
$config = @{
    # Required: Array of OS identifiers
    os = @("ubuntu-latest", "windows-latest", "macos-latest")
    
    # Optional: Additional dimensions (arrays)
    node_version = @("18.x", "20.x")
    python_version = @("3.9", "3.10", "3.11")
    
    # Optional: Exclude specific combinations
    exclude = @(
        @{ os = "windows-latest"; node_version = "18.x" }
        @{ os = "macos-latest"; python_version = "3.9" }
    )
    
    # Optional: Include additional combinations
    include = @(
        @{ os = "custom-runner"; node_version = "21.x"; experimental = $true }
    )
    
    # Optional: GitHub Actions configuration
    max_parallel = 5
    fail_fast = $false
    max_matrix_size = 256
}
```

### Output Format
```json
{
  "include": [
    { "os": "ubuntu-latest", "node_version": "18.x" },
    { "os": "ubuntu-latest", "node_version": "20.x" },
    { "os": "windows-latest", "node_version": "20.x" }
  ],
  "max-parallel": 5,
  "fail-fast": false
}
```

## Testing

### Test Coverage (12 tests)
- ✅ Basic matrix generation
- ✅ Multi-dimensional matrices (cartesian product)
- ✅ Exclude rules with partial matching
- ✅ Include rules for additional combinations
- ✅ Max-parallel configuration
- ✅ Fail-fast configuration
- ✅ Matrix size validation
- ✅ JSON output format validation
- ✅ Complex 3D scenarios
- ✅ Error handling (missing OS)
- ✅ Error handling (size exceeded)
- ✅ All 5 fixture-based integration tests

### Run Tests Locally
```bash
# Run all tests
Invoke-Pester -Path Test-MatrixGenerator.ps1 -Verbose

# Run through GitHub Actions (act)
act push --rm
```

## GitHub Actions Integration

### Workflow Features
- **Triggers**: push, pull_request, workflow_dispatch, scheduled (weekly)
- **Permissions**: Minimal (contents: read only)
- **Steps**:
  1. Create test fixtures
  2. Run Pester unit tests
  3. Test with JSON fixtures
  4. Validate error handling

### Usage in Your Workflow
```yaml
- name: Generate Build Matrix
  shell: pwsh
  run: |
    . ./New-GitHubActionsMatrix.ps1
    $config = Get-Content matrix-config.json | ConvertFrom-Json -AsHashtable
    $matrix = New-GitHubActionsMatrix -Config $config
    $json = $matrix | ConvertTo-Json -Compress
    Write-Host "::set-output name=matrix::$json"
```

## Examples

### Example 1: Basic OS Matrix
```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest")
}
# Generates: 2 combinations
```

### Example 2: Multi-Dimensional Matrix
```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest")
    node_version = @("18.x", "20.x")
}
# Generates: 2 × 2 = 4 combinations
```

### Example 3: With Exclusions
```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest", "macos-latest")
    version = @("10", "11", "12")
    exclude = @(
        @{ os = "windows-latest"; version = "10" }
    )
}
# Generates: (3 × 3) - 1 = 8 combinations
```

### Example 4: Complex Configuration
```powershell
$config = @{
    os = @("ubuntu-latest", "windows-latest", "macos-latest")
    node_version = @("18.x", "20.x")
    experimental = @($false, $true)
    exclude = @(
        @{ os = "windows-latest"; experimental = $true }
        @{ os = "macos-latest"; node_version = "18.x" }
    )
    include = @(
        @{ os = "custom-arm64"; node_version = "20.x"; experimental = $false }
    )
    max_parallel = 5
    fail_fast = $true
}
# Generates: (3 × 2 × 2) - 4 + 1 = 9 combinations
```

## Error Handling

### Missing OS Configuration
```
Configuration must contain 'os' array.
```

### Empty OS Array
```
OS configuration cannot be empty.
```

### Matrix Size Exceeded
```
Matrix size (256) exceeds maximum allowed size (128).
```

## Validation

✅ **actionlint**: PASSED (YAML validation)  
✅ **Pester**: 12/12 tests passing  
✅ **act**: Workflow execution successful  
✅ **PowerShell**: v7.6.4+ compatible  

## Performance

| Operation | Time |
|-----------|------|
| Basic matrix (2 combinations) | < 10ms |
| 2D matrix (4 combinations) | < 20ms |
| JSON conversion | < 50ms |
| Full test suite | ~989ms |
| Workflow execution | ~4.1s |

## Requirements

- PowerShell 7.x (pwsh)
- Pester v5+ (for testing)
- GitHub Actions (for CI/CD)
- Docker (for act validation)

## Maintenance

- All tests pass ✅
- No external dependencies
- Pure PowerShell implementation
- Compatible with GitHub Actions default runner containers

## License

This implementation is provided as-is for use in GitHub Actions workflows.

## Support

For issues or improvements, refer to:
- `IMPLEMENTATION.md` - Technical documentation
- `Test-MatrixGenerator.ps1` - Test examples
- `act-result.txt` - Execution logs
