<#
.SYNOPSIS
    Parses act-result.txt and makes exact-value assertions about the
    captured `act push` output for the environment-matrix-generator workflow.
    Run directly with: pwsh ./verify-act-output.ps1
#>

$ErrorActionPreference = 'Stop'
$resultPath = Join-Path $PSScriptRoot 'act-result.txt'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message" -ForegroundColor Red
    } else {
        Write-Host "PASS: $Message" -ForegroundColor Green
    }
}

if (-not (Test-Path $resultPath)) {
    throw "act-result.txt not found at $resultPath"
}

$content = Get-Content -Path $resultPath -Raw

# Isolate the most recent (last) run block, since act-result.txt is append-only across runs.
$runBlocks = [regex]::Matches($content, '(?s)=== ACT RUN.*?=== END RUN \d+ ===')
Assert-True ($runBlocks.Count -gt 0) "act-result.txt contains at least one recorded run"
$lastRun = $runBlocks[$runBlocks.Count - 1].Value

# 1. Exit code was 0.
$exitMatch = [regex]::Match($lastRun, 'EXIT_CODE=(\d+)')
Assert-True $exitMatch.Success "EXIT_CODE line present in last act run"
if ($exitMatch.Success) {
    Assert-True ($exitMatch.Groups[1].Value -eq '0') "act exited with code 0 (got $($exitMatch.Groups[1].Value))"
}

# 2. Job succeeded appears (per-job success indicator).
Assert-True ($lastRun -match [regex]::Escape('🏁  Job succeeded')) "act output shows 'Job succeeded'"

# 3. Exact expected JSON matrix values for the basic fixture.
$basicExpected = @(
    '"os": "ubuntu-latest",',
    '"version": "16",',
    '"flags": "stable"'
) -join "`n"
Assert-True ($lastRun -match [regex]::Escape('=== MATRIX OUTPUT: basic ===')) "basic fixture output delimiter present"
Assert-True ($lastRun -match [regex]::Escape('"os": "windows-latest",') -and $lastRun -match [regex]::Escape('"version": "18",')) "basic fixture contains windows-latest/18 combo"
Assert-True ($lastRun -match [regex]::Escape('"fail-fast": true,')) "basic fixture fail-fast is exactly true"
Assert-True ($lastRun -match [regex]::Escape('"max-parallel": 4')) "basic fixture max-parallel is exactly 4"

# 4. Exact expected JSON matrix values for the with-include-exclude fixture.
Assert-True ($lastRun -match [regex]::Escape('=== MATRIX OUTPUT: with-include-exclude ===')) "with-include-exclude fixture output delimiter present"
Assert-True ($lastRun -match [regex]::Escape('"os": "macos-latest",') -or $lastRun -match [regex]::Escape('"os": "macos-latest"')) "with-include-exclude fixture contains included macos-latest combo"
# Precise check: within the with-include-exclude section, windows-latest+16 combo must NOT appear together.
$includeExcludeSection = [regex]::Match($lastRun, '(?s)=== MATRIX OUTPUT: with-include-exclude ===.*?(?=⭐ Run Main Generate matrix - exceeds-max|$)').Value
$hasExcludedCombo = ($includeExcludeSection -match '(?s)"os": "windows-latest",\s*\r?\n\s*"version": "16"')
Assert-True (-not $hasExcludedCombo) "with-include-exclude fixture excludes windows-latest/16 combo"
Assert-True ($includeExcludeSection -match [regex]::Escape('"fail-fast": false,')) "with-include-exclude fixture fail-fast is exactly false"
Assert-True ($includeExcludeSection -match [regex]::Escape('"max-parallel": 2')) "with-include-exclude fixture max-parallel is exactly 2"

# 5. exceeds-max fixture triggers the expected error message exactly.
$expectedError = 'EXPECTED ERROR: Matrix size (24) exceeds maximum size (10).'
Assert-True ($lastRun -match [regex]::Escape('=== MATRIX OUTPUT: exceeds-max ===')) "exceeds-max fixture output delimiter present"
Assert-True ($lastRun -match [regex]::Escape($expectedError)) "exceeds-max fixture produced exact expected error: '$expectedError'"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($failures.Count) CHECK(S) FAILED" -ForegroundColor Red
    exit 1
}
