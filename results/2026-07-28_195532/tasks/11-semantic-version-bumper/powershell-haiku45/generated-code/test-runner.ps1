# Test runner - executes multiple test scenarios via act
# Tests the workflow with different commit scenarios

param(
    [int]$MaxRuns = 3
)

# Clean up previous results
if (Test-Path "act-result.txt") {
    Remove-Item "act-result.txt"
}

$testCases = @(
    @{
        name = "Test Case 1: Minor Bump (feat commit)"
        version = "1.0.0"
        commits = @(
            "feat: add new dashboard widget"
        )
        expectedVersion = "1.1.0"
        expectedBump = "minor"
    },
    @{
        name = "Test Case 2: Patch Bump (fix commit)"
        version = "2.1.0"
        commits = @(
            "fix: resolve null reference error"
        )
        expectedVersion = "2.1.1"
        expectedBump = "patch"
    },
    @{
        name = "Test Case 3: Major Bump (breaking change)"
        version = "1.5.2"
        commits = @(
            "feat: redesign API endpoints",
            "BREAKING CHANGE: removed v1 API support"
        )
        expectedVersion = "2.0.0"
        expectedBump = "major"
    }
)

$resultsLog = @()

for ($i = 0; $i -lt [Math]::Min($testCases.Count, $MaxRuns); $i++) {
    $testCase = $testCases[$i]
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host $testCase.name -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan

    # Create test package.json
    $packageJson = @{
        version = $testCase.version
        name = "test-app"
        description = "Test package"
    } | ConvertTo-Json
    Set-Content -Path ./package.json -Value $packageJson -Encoding UTF8

    # Create commits.log
    $commitContent = $testCase.commits -join "`n"
    Set-Content -Path ./commits.log -Value $commitContent -Encoding UTF8

    Write-Host "Initial version: $($testCase.version)" -ForegroundColor Yellow
    Write-Host "Expected new version: $($testCase.expectedVersion)" -ForegroundColor Yellow
    Write-Host "Expected bump type: $($testCase.expectedBump)" -ForegroundColor Yellow

    # Run act
    Write-Host "Running workflow via act..." -ForegroundColor Gray
    $actOutput = act push --rm -W .github/workflows/semantic-version-bumper.yml 2>&1

    # Append to cumulative results
    Add-Content -Path "act-result.txt" -Value "`n`n$('='*60)`n$($testCase.name)`n$('='*60)`n"
    Add-Content -Path "act-result.txt" -Value $actOutput

    # Parse results - need to handle act output format with prefixes
    $lines = $actOutput -split "`n"
    $actualVersion = "NOT FOUND"
    $actualBump = "NOT FOUND"
    $jobPassed = $false

    foreach ($line in $lines) {
        if ($line -match "New Version:\s*(.+)$") {
            $actualVersion = $matches[1].Trim()
        }
        if ($line -match "Bump Type:\s*(.+)$") {
            $actualBump = $matches[1].Trim()
        }
        if ($line -match "Job succeeded") {
            $jobPassed = $true
        }
    }

    $versionColor = $actualVersion -eq $testCase.expectedVersion ? "Green" : "Red"
    $bumpColor = $actualBump -eq $testCase.expectedBump ? "Green" : "Red"
    $jobColor = $jobPassed ? "Green" : "Red"
    $jobStatus = $jobPassed ? "PASSED" : "FAILED"

    Write-Host "Actual version: $actualVersion" -ForegroundColor $versionColor
    Write-Host "Actual bump: $actualBump" -ForegroundColor $bumpColor
    Write-Host "Job status: $jobStatus" -ForegroundColor $jobColor

    $result = @{
        testName = $testCase.name
        initialVersion = $testCase.version
        expectedVersion = $testCase.expectedVersion
        actualVersion = $actualVersion
        expectedBump = $testCase.expectedBump
        actualBump = $actualBump
        versionMatch = $actualVersion -eq $testCase.expectedVersion
        bumpMatch = $actualBump -eq $testCase.expectedBump
        jobPassed = $jobPassed
    }

    $resultsLog += $result
}

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

$passed = @($resultsLog | Where-Object { $_.versionMatch -and $_.bumpMatch -and $_.jobPassed }).Count
$total = $resultsLog.Count

foreach ($result in $resultsLog) {
    $status = ($result.versionMatch -and $result.bumpMatch -and $result.jobPassed) ? "✓" : "✗"
    $statusColor = $status -eq "✓" ? "Green" : "Red"
    Write-Host "$status $($result.testName)" -ForegroundColor $statusColor
    if (-not $result.versionMatch) { Write-Host "  Version mismatch: expected $($result.expectedVersion), got $($result.actualVersion)" -ForegroundColor Red }
    if (-not $result.bumpMatch) { Write-Host "  Bump mismatch: expected $($result.expectedBump), got $($result.actualBump)" -ForegroundColor Red }
    if (-not $result.jobPassed) { Write-Host "  Job failed" -ForegroundColor Red }
}

Write-Host ""
$summaryColor = $passed -eq $total ? "Green" : "Yellow"
Write-Host "Total: $passed/$total tests passed" -ForegroundColor $summaryColor

# Exit with appropriate code
$exitCode = $passed -eq $total ? 0 : 1
exit $exitCode
