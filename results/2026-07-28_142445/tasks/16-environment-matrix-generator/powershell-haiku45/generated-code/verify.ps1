# Verification script for Environment Matrix Generator
# Ensures all components are in place and functioning correctly

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$warnings = @()
$errors = @()
$successes = @()

function Test-Component {
    param([string]$Name, [string]$Path, [string]$Description)

    if (Test-Path $Path) {
        $successes += "✓ $Name - $Description"
        return $true
    }
    else {
        $errors += "✗ $Name - $Description (NOT FOUND: $Path)"
        return $false
    }
}

function Test-File-Content {
    param([string]$Name, [string]$Path, [string]$SearchPattern, [string]$Description)

    if (-not (Test-Path $Path)) {
        $errors += "✗ $Name - File not found: $Path"
        return $false
    }

    $content = Get-Content $Path -Raw
    if ($content -match $SearchPattern) {
        $successes += "✓ $Name - $Description"
        return $true
    }
    else {
        $errors += "✗ $Name - $Description (Pattern not found: $SearchPattern)"
        return $false
    }
}

Write-Host "=================================================="
Write-Host "Environment Matrix Generator - Verification"
Write-Host "=================================================="
Write-Host ""

# Phase 1: Structure verification
Write-Host "Phase 1: Project Structure"
Write-Host "--"
Test-Component "Script" "./src/EnvironmentMatrixGenerator.ps1" "Main implementation"
Test-Component "Tests" "./tests/EnvironmentMatrixGenerator.Tests.ps1" "Pester test suite"
Test-Component "Workflow" "./.github/workflows/environment-matrix-generator.yml" "GitHub Actions pipeline"
Test-Component "Fixture 1" "./tests/fixtures/simple-matrix.json" "Simple test configuration"
Test-Component "Fixture 2" "./tests/fixtures/matrix-with-rules.json" "Complex test configuration"
Test-Component "README" "./README.md" "Documentation"
Write-Host ""

# Phase 2: Content verification
Write-Host "Phase 2: File Contents"
Write-Host "--"
Test-File-Content "Function: New-EnvironmentMatrix" "./src/EnvironmentMatrixGenerator.ps1" "function New-EnvironmentMatrix" "Core function defined"
Test-File-Content "Function: Get-CartesianProduct" "./src/EnvironmentMatrixGenerator.ps1" "function Get-CartesianProduct" "Helper function defined"
Test-File-Content "Function: Test-CombinationMatches" "./src/EnvironmentMatrixGenerator.ps1" "function Test-CombinationMatches" "Helper function defined"
Test-File-Content "Test Suite" "./tests/EnvironmentMatrixGenerator.Tests.ps1" "Describe.*EnvironmentMatrixGenerator" "Pester test suite"
Test-File-Content "Workflow Jobs" "./.github/workflows/environment-matrix-generator.yml" "jobs:" "Job definitions"
Test-File-Content "Workflow Triggers" "./.github/workflows/environment-matrix-generator.yml" "on:" "Trigger events"
Write-Host ""

# Phase 3: Functionality verification
Write-Host "Phase 3: Functionality Tests"
Write-Host "--"

try {
    . ./src/EnvironmentMatrixGenerator.ps1
    $successes += "✓ Script Loading - Successfully loaded main script"

    # Test basic functionality
    $config = @{
        os = @("ubuntu-latest", "windows-latest")
        version = @("18", "20")
    }

    $result = New-EnvironmentMatrix -Configuration $config
    if ($result -and $result.include.Count -eq 4) {
        $successes += "✓ Basic Matrix Generation - Correctly generated 4 combinations (2×2)"
    }
    else {
        $errors += "✗ Basic Matrix Generation - Expected 4 combinations, got $($result.include.Count)"
    }

    # Test with rules
    $config2 = @{
        os = @("ubuntu-latest", "windows-latest")
        version = @("18", "20")
        exclude = @(@{ os = "windows-latest"; version = "18" })
    }

    $result2 = New-EnvironmentMatrix -Configuration $config2
    if ($result2.include.Count -eq 3) {
        $successes += "✓ Exclude Rules - Correctly excluded 1 combination"
    }
    else {
        $errors += "✗ Exclude Rules - Expected 3 combinations, got $($result2.include.Count)"
    }

    # Test validation
    $config3 = @{
        os = @("ubuntu-latest", "windows-latest", "macos-latest")
        version = @("18", "20")
    }

    $result3 = New-EnvironmentMatrix -Configuration $config3 -MaxMatrixSize 5
    if ($result3.valid -eq $false -and $result3.error -match "exceeds maximum") {
        $successes += "✓ Size Validation - Correctly rejected oversized matrix"
    }
    else {
        $errors += "✗ Size Validation - Expected error for oversized matrix"
    }
}
catch {
    $errors += "✗ Functionality Tests - Exception: $_"
}

Write-Host ""

# Phase 4: Pester test results
Write-Host "Phase 4: Pester Test Execution"
Write-Host "--"

try {
    $testResults = Invoke-Pester ./tests/EnvironmentMatrixGenerator.Tests.ps1 -PassThru

    if ($testResults.FailedCount -eq 0) {
        $successes += "✓ All Pester Tests - $($testResults.PassedCount) tests passed"
    }
    else {
        $errors += "✗ Pester Tests - $($testResults.FailedCount) tests failed"
        if ($testResults.FailedCount -gt 0) {
            foreach ($test in $testResults.Failed) {
                $errors += "  - Failed: $($test.Name)"
            }
        }
    }
}
catch {
    $errors += "✗ Pester Test Execution - Exception: $_"
}

Write-Host ""

# Phase 5: Workflow validation
Write-Host "Phase 5: Workflow Validation"
Write-Host "--"

try {
    $yaml = Get-Content ./.github/workflows/environment-matrix-generator.yml -Raw

    if ($yaml -match "name:\s+Environment Matrix Generator Tests") {
        $successes += "✓ Workflow Name - Correctly defined"
    }

    if ($yaml -match "shell:\s+pwsh") {
        $successes += "✓ PowerShell Shell - Correctly configured"
    }

    if ($yaml -match "uses:\s+actions/checkout@v4") {
        $successes += "✓ Checkout Action - Using v4"
    }

    if ($yaml -match "permissions:\s+contents:\s+read") {
        $successes += "✓ Permissions - Least privilege (contents:read)"
    }

    # Check for triggers
    if ($yaml -match "on:" -and ($yaml -match "push:" -or $yaml -match "pull_request:")) {
        $successes += "✓ Workflow Triggers - push and pull_request configured"
    }
}
catch {
    $errors += "✗ Workflow Validation - Exception: $_"
}

Write-Host ""

# Summary
Write-Host "=================================================="
Write-Host "Verification Summary"
Write-Host "=================================================="
Write-Host ""

if ($Verbose -or $errors.Count -gt 0 -or $warnings.Count -gt 0) {
    if ($successes.Count -gt 0) {
        Write-Host "✓ Successes ($($successes.Count)):"
        $successes | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
    }

    if ($warnings.Count -gt 0) {
        Write-Host "⚠ Warnings ($($warnings.Count)):"
        $warnings | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
    }

    if ($errors.Count -gt 0) {
        Write-Host "✗ Errors ($($errors.Count)):"
        $errors | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
    }
}

$total = $successes.Count + $errors.Count
$percentage = if ($total -gt 0) { [math]::Round(($successes.Count / $total) * 100, 0) } else { 0 }

Write-Host "Overall: $($successes.Count)/$total passed ($percentage%)"

if ($errors.Count -eq 0) {
    Write-Host "✓ All verification checks passed!"
    exit 0
}
else {
    Write-Host "✗ Verification failed with $($errors.Count) error(s)"
    exit 1
}
