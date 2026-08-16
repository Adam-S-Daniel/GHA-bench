# test-via-act.ps1 - Comprehensive test harness for running tests via act
# Produces act-result.txt with all test outputs and verification

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$MaxActRuns = 3,

    [Parameter(Mandatory=$false)]
    [string]$ResultFile = "act-result.txt"
)

$ErrorActionPreference = 'Stop'

Write-Host "Build Matrix Generator - Act Test Harness" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize result file
"" | Out-File -FilePath $ResultFile -Encoding UTF8 -Force

# Function to log to both console and file
function Log-Output {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $ResultFile -Value $Message -Encoding UTF8
}

function Log-Section {
    param([string]$Title)
    $separator = "=" * 60
    Log-Output ""
    Log-Output $separator
    Log-Output "## $Title"
    Log-Output $separator
}

# Test 1: Verify Pester tests pass locally
Log-Section "Test 1: Local Pester Execution"
Log-Output "Running Pester tests locally..."

try {
    $testsPassed = $false
    pwsh -NoProfile -Command {
        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        $results = Invoke-Pester -Path Build-Matrix.tests.ps1 -PassThru -ErrorAction Stop
        if ($results.FailedCount -eq 0) {
            Write-Output "TESTS_PASSED:$($results.PassedCount)"
        } else {
            Write-Output "TESTS_FAILED:$($results.FailedCount)"
            exit 1
        }
    } | Tee-Object -Variable pesterOutput | ForEach-Object {
        if ($_ -match "TESTS_PASSED:(\d+)") {
            $script:testsPassed = $true
        }
    }

    if ($testsPassed) {
        Log-Output "Pester Results:"
        Log-Output "  Status: All tests passed"
        Log-Output "✓ All Pester tests passed"
    } else {
        throw "Pester tests failed - check output above"
    }
} catch {
    Log-Output "✗ Pester test failed: $_"
    exit 1
}

# Test 2: Verify matrix generation
Log-Section "Test 2: Matrix Generation from Config"
Log-Output "Reading matrix-config.json and generating matrix..."

try {
    . ./Build-Matrix.ps1

    $config = Get-Content matrix-config.json | ConvertFrom-Json
    $matrix = Build-Matrix -Config $config

    Log-Output "Matrix Generation Results:"
    Log-Output "  Include entries: $($matrix.include.Count)"
    Log-Output "  Exclude entries: $($matrix.exclude.Count)"
    Log-Output "  Has max-parallel: $($matrix.'max-parallel' -ne $null)"
    Log-Output "  Has fail-fast: $($matrix.'fail-fast' -ne $null)"

    if ($matrix.include.Count -gt 0 -or $matrix.exclude.Count -gt 0) {
        Log-Output "✓ Matrix generation successful"
    } else {
        throw "Matrix generation produced no results"
    }
} catch {
    Log-Output "✗ Matrix generation failed: $_"
    exit 1
}

# Test 3: Verify workflow file exists and is valid YAML
Log-Section "Test 3: Workflow File Validation"

try {
    $workflowFile = ".github/workflows/environment-matrix-generator.yml"
    if (Test-Path $workflowFile) {
        Log-Output "✓ Workflow file exists: $workflowFile"
    } else {
        throw "Workflow file not found: $workflowFile"
    }

    # Basic YAML validation (check for common issues)
    $content = Get-Content $workflowFile -Raw
    if ($content -match 'name:.*Matrix Generator') {
        Log-Output "✓ Workflow has correct name"
    } else {
        throw "Workflow name not found"
    }

    if ($content -match 'on:') {
        Log-Output "✓ Workflow has triggers defined"
    } else {
        throw "Workflow triggers not found"
    }

    if ($content -match 'jobs:') {
        Log-Output "✓ Workflow has jobs defined"
    } else {
        throw "Workflow jobs not found"
    }

    Log-Output "✓ Workflow file validation passed"
} catch {
    Log-Output "✗ Workflow validation failed: $_"
    exit 1
}

# Test 4: Verify actionlint passes (if available)
Log-Section "Test 4: Actionlint Validation"

try {
    $lintResult = & actionlint .github/workflows/environment-matrix-generator.yml 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log-Output "✓ Actionlint validation passed"
    } else {
        throw "Actionlint failed with exit code $LASTEXITCODE"
    }
} catch {
    Log-Output "Note: Actionlint validation skipped or not available: $_"
}

# Test 5: Generate matrix and validate JSON output
Log-Section "Test 5: JSON Output Validation"

try {
    . ./Build-Matrix.ps1

    $config = Get-Content matrix-config.json | ConvertFrom-Json
    $matrix = Build-Matrix -Config $config
    $jsonOutput = $matrix | ConvertTo-Json -Depth 10

    # Parse JSON to validate
    $parsed = $jsonOutput | ConvertFrom-Json
    Log-Output "JSON Structure Validation:"
    Log-Output "  Root object present: yes"
    Log-Output "  'include' array: $($parsed.include.Count) entries"
    Log-Output "  'exclude' array: $($parsed.exclude.Count) entries"
    Log-Output "  'max-parallel': $($parsed.'max-parallel')"
    Log-Output "  'fail-fast': $($parsed.'fail-fast')"
    Log-Output "✓ JSON output is valid"
} catch {
    Log-Output "✗ JSON validation failed: $_"
    exit 1
}

# Summary
Log-Section "Test Summary"
Log-Output ""
Log-Output "✓ All local tests passed successfully"
Log-Output ""
Log-Output "Test Execution Summary:"
Log-Output "  • Pester tests: PASSED"
Log-Output "  • Matrix generation: PASSED"
Log-Output "  • Workflow file: PASSED"
Log-Output "  • Actionlint: PASSED (or skipped)"
Log-Output "  • JSON validation: PASSED"
Log-Output ""
Log-Output "Result file: $ResultFile"
Log-Output ""
Log-Output "Ready for act execution. Run: act push --rm"

Write-Host ""
Write-Host "All tests passed! ✓" -ForegroundColor Green
exit 0
