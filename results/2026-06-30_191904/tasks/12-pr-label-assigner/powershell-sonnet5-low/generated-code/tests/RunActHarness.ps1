# RunActHarness.ps1
# Runs the GitHub Actions workflow through `act`, captures the output for
# every test case into act-result.txt, and asserts exact expected values.
#
# This is the harness required by the task: all functional testing of the
# label-assignment behavior happens through the real GitHub Actions
# pipeline executed locally via `act`, not by calling the PowerShell script
# directly.

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/.."
$resultPath = Join-Path $repoRoot "act-result.txt"

if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

Write-Host "Running act push --pull=false --rm ..."
$actOutput = & act push --pull=false --rm 2>&1
$actExitCode = $LASTEXITCODE

$delimiter = "=" * 80
$header = @"
$delimiter
ACT RUN - single push event exercising both jobs (unit-tests, assign-labels)
Exit code: $actExitCode
$delimiter
"@

$header | Out-File -FilePath $resultPath -Encoding utf8
$actOutput | Out-File -FilePath $resultPath -Append -Encoding utf8
"$delimiter" | Out-File -FilePath $resultPath -Append -Encoding utf8

$outputText = ($actOutput -join "`n") -replace "`e\[[0-9;]*m", ""

$failures = @()

if ($actExitCode -ne 0) {
    $failures += "act exited with code $actExitCode, expected 0"
}

# Every job must report success.
if (($outputText | Select-String -Pattern "Job succeeded" -AllMatches).Matches.Count -lt 2) {
    $failures += "Expected 2 'Job succeeded' occurrences (unit-tests, assign-labels)"
}
if ($outputText -match "Job failed") {
    $failures += "Found a 'Job failed' occurrence in act output"
}

# Pester results embedded in the unit-tests job output.
if ($outputText -notmatch [regex]::Escape("Tests Passed: 11, Failed: 0")) {
    $failures += "Expected exact Pester summary 'Tests Passed: 11, Failed: 0' in act output"
}

# Fixture case 1: docs-and-api -> exact label set, priority order tests(3) > api(2) > documentation(1)
if ($outputText -notmatch [regex]::Escape("CASE: docs-and-api")) {
    $failures += "Missing 'CASE: docs-and-api' in act output"
}
if ($outputText -notmatch [regex]::Escape("LABELS: tests,api,documentation")) {
    $failures += "Expected exact 'LABELS: tests,api,documentation' for docs-and-api case"
}

# Fixture case 2: priority-conflict -> exact label order high-priority(10) > low-priority(1)
if ($outputText -notmatch [regex]::Escape("CASE: priority-conflict")) {
    $failures += "Missing 'CASE: priority-conflict' in act output"
}
if ($outputText -notmatch [regex]::Escape("LABELS: high-priority,low-priority")) {
    $failures += "Expected exact 'LABELS: high-priority,low-priority' for priority-conflict case"
}

$summary = @"
$delimiter
ASSERTION SUMMARY
$delimiter
"@
$summary | Out-File -FilePath $resultPath -Append -Encoding utf8

if ($failures.Count -eq 0) {
    "ALL ASSERTIONS PASSED" | Out-File -FilePath $resultPath -Append -Encoding utf8
    Write-Host "ALL ASSERTIONS PASSED" -ForegroundColor Green
    exit 0
} else {
    foreach ($f in $failures) {
        "FAILED: $f" | Out-File -FilePath $resultPath -Append -Encoding utf8
    }
    Write-Host "ASSERTIONS FAILED:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
