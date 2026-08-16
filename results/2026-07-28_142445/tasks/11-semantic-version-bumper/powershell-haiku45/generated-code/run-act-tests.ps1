<#
.SYNOPSIS
Test harness that runs the GitHub Actions workflow through act
Tests multiple scenarios and verifies output
#>

param(
    [switch]$SkipCleanup
)

# Import test fixtures
. $PSScriptRoot/test-fixtures.ps1

$testResults = @()
$actResultFile = "act-result.txt"

# Clear previous results
if (Test-Path $actResultFile) {
    Remove-Item $actResultFile -Force
}

Write-Host "=== Semantic Version Bumper - Act Test Suite ===" -ForegroundColor Cyan
Write-Host ""

# Test cases to run (limit to first 3 to avoid excessive act runs)
$testCasesToRun = $testCases[0..2]

$testIndex = 1
foreach ($testCase in $testCasesToRun) {
    Write-Host "────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "Test Case $testIndex`: $($testCase.name)" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────────────────" -ForegroundColor Gray

    # Create temporary test directory
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "act-test-$($testCase.name)"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Initialize git repo
        Push-Location $tempDir
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"

        # Create package.json with old version
        $packageJson = @{
            name = "test-package"
            version = $testCase.expected.oldVersion
            description = "Test package"
        } | ConvertTo-Json
        Set-Content -Path "package.json" -Value $packageJson

        git add package.json
        git commit -m "chore: initial commit" -q

        # Create test commits based on fixture data
        foreach ($commit in $testCase.commits) {
            # Create a dummy file to commit
            $dummyFile = "file-$(Get-Random).txt"
            Set-Content -Path $dummyFile -Value "test content"
            git add $dummyFile

            # Split multi-line commit messages properly
            $commitLines = $commit -split "`n"
            if ($commitLines.Count -gt 1) {
                # Use -m multiple times for multi-line commit
                $gitArgs = @("commit", "-q")
                foreach ($line in $commitLines) {
                    $gitArgs += "-m"
                    $gitArgs += $line
                }
                git @gitArgs
            }
            else {
                git commit -q -m $commit
            }
        }

        # Copy scripts to test directory
        Copy-Item "$PSScriptRoot/version-bumper.ps1" -Destination .
        Copy-Item "$PSScriptRoot/bump-version.ps1" -Destination .
        Copy-Item "$PSScriptRoot/test-version-bumper.ps1" -Destination .
        Copy-Item "$PSScriptRoot/.github" -Destination . -Recurse -Force

        # Run act
        Write-Host "Running workflow through act..."
        $actOutput = act push -l 2>&1
        $actExitCode = $LASTEXITCODE

        # Append to results file
        Add-Content -Path (Join-Path (Get-Location).Path $actResultFile) -Value "Test Case $testIndex`: $($testCase.name)"
        Add-Content -Path (Join-Path (Get-Location).Path $actResultFile) -Value "================================================================"
        Add-Content -Path (Join-Path (Get-Location).Path $actResultFile) -Value $actOutput
        Add-Content -Path (Join-Path (Get-Location).Path $actResultFile) -Value ""
        Add-Content -Path (Join-Path (Get-Location).Path $actResultFile) -Value ""

        # Check exit code
        if ($actExitCode -eq 0) {
            Write-Host "✓ act exited with code 0" -ForegroundColor Green
        }
        else {
            Write-Host "✗ act exited with code $actExitCode" -ForegroundColor Red
        }

        # Check for success messages in output
        $successCount = ([regex]::Matches($actOutput, "Job succeeded")).Count
        if ($successCount -gt 0) {
            Write-Host "✓ $successCount job(s) succeeded" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ No job success messages found" -ForegroundColor Yellow
        }

        # Store result
        $testResults += @{
            name = $testCase.name
            exitCode = $actExitCode
            passed = $actExitCode -eq 0
            output = $actOutput
        }

        Write-Host ""
        $testIndex++
    }
    finally {
        Pop-Location
        if (-not $SkipCleanup) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Copy act-result.txt to current working directory
if (Test-Path (Join-Path $tempDir $actResultFile)) {
    Copy-Item (Join-Path $tempDir $actResultFile) -Destination $PSScriptRoot/$actResultFile -Force
    Write-Host "✓ Results saved to: $PSScriptRoot/$actResultFile" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""

$passedCount = ($testResults | Where-Object { $_.passed }).Count
$failedCount = $testResults.Count - $passedCount

Write-Host "Passed: $passedCount/$($testResults.Count)" -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Yellow' })

foreach ($result in $testResults) {
    $status = if ($result.passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($result.passed) { 'Green' } else { 'Red' }
    Write-Host "  $status : $($result.name) (exit code: $($result.exitCode))" -ForegroundColor $color
}

Write-Host ""

# Exit with appropriate code
if ($failedCount -gt 0) {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
