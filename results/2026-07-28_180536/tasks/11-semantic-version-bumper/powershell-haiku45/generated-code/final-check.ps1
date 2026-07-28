#!/usr/bin/env pwsh

Write-Host "=== FINAL VERIFICATION CHECKLIST ===" -ForegroundColor Cyan
Write-Host ""

$allGood = $true

# Check 1: Files exist
Write-Host "[1/5] Verifying all required files exist..." -ForegroundColor Yellow
$requiredFiles = @(
    "src/semver-bumper.ps1",
    "src/run-semantic-bump.ps1",
    "tests/semver-bumper.Tests.ps1",
    "fixtures/test-cases.ps1",
    ".github/workflows/semantic-version-bumper.yml",
    "package.json",
    "act-result.txt"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "  ✅ $file"
    } else {
        Write-Host "  ❌ $file (MISSING!)"
        $allGood = $false
    }
}

# Check 2: Run unit tests
Write-Host ""
Write-Host "[2/5] Running Pester tests..." -ForegroundColor Yellow
$testResults = Invoke-Pester -Path tests/semver-bumper.Tests.ps1 -PassThru -Quiet
Write-Host "  Tests: $($testResults.PassedCount) passed, $($testResults.FailedCount) failed"
if ($testResults.FailedCount -gt 0) {
    Write-Host "  ❌ Tests FAILED!"
    $allGood = $false
} else {
    Write-Host "  ✅ All tests passed"
}

# Check 3: Validate workflow
Write-Host ""
Write-Host "[3/5] Validating workflow with actionlint..." -ForegroundColor Yellow
$lintResult = & actionlint .github/workflows/semantic-version-bumper.yml 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ Workflow validation passed"
} else {
    Write-Host "  ❌ Workflow validation failed"
    Write-Host "  $lintResult"
    $allGood = $false
}

# Check 4: Verify act-result.txt
Write-Host ""
Write-Host "[4/5] Verifying act results artifact..." -ForegroundColor Yellow
if (Test-Path "act-result.txt") {
    $resultSize = (Get-Item "act-result.txt").Length
    $resultLines = (Get-Content "act-result.txt" | Measure-Object -Line).Lines
    $jobCount = (Get-Content "act-result.txt" | Select-String "Job succeeded" | Measure-Object).Count
    
    Write-Host "  ✅ act-result.txt exists"
    Write-Host "    - Size: $resultSize bytes"
    Write-Host "    - Lines: $resultLines"
    Write-Host "    - Jobs succeeded: $jobCount"
    
    if ($jobCount -lt 2) {
        Write-Host "  ⚠️  Warning: Expected 3+ successful jobs"
    }
} else {
    Write-Host "  ❌ act-result.txt not found"
    $allGood = $false
}

# Check 5: Quick script integration test
Write-Host ""
Write-Host "[5/5] Testing script integration..." -ForegroundColor Yellow
try {
    . ./src/semver-bumper.ps1
    
    $version = Get-NextVersion -CurrentVersion "1.0.0" -CommitMessages @("feat: test")
    if ($version -eq "1.1.0") {
        Write-Host "  ✅ Script functions work correctly (1.0.0 + feat → 1.1.0)"
    } else {
        Write-Host "  ❌ Script returned unexpected version: $version"
        $allGood = $false
    }
} catch {
    Write-Host "  ❌ Script integration test failed: $_"
    $allGood = $false
}

# Summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "✅ ALL CHECKS PASSED - Project is ready!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ SOME CHECKS FAILED - Review above" -ForegroundColor Red
    exit 1
}
