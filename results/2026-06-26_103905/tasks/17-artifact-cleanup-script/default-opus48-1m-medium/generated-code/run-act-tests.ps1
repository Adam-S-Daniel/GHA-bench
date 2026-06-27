#!/usr/bin/env pwsh
<#
.SYNOPSIS
    End-to-end test harness: runs every test case through the GitHub Actions
    workflow using `act`, captures output to act-result.txt, and asserts on the
    EXACT expected values for each case.

.DESCRIPTION
    For each case:
      1. Build a clean temp git repo containing the project files plus the case's
         fixture data copied to fixtures/scenario.json (the path the workflow reads).
      2. Run `act push --rm`, capturing combined output.
      3. Append the output to act-result.txt, clearly delimited.
      4. Assert act exited 0, every job reported success, and the parsed output
         matches the known-good values for that case.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot   = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'
Set-Content -LiteralPath $resultFile -Value "Artifact Cleanup - act test run`n" -Encoding utf8

# Project files copied into each isolated temp repo.
$projectFiles = @(
    'ArtifactCleanup.psm1',
    'ArtifactCleanup.Tests.ps1',
    'Invoke-Cleanup.ps1',
    '.actrc'
)

# ----------------------------------------------------------------------------
# Test cases: fixture + the exact assertions for that fixture's output.
# Expected values were hand-derived from the retention policy semantics.
# ----------------------------------------------------------------------------
$cases = @(
    @{
        Name    = 'basic-maxage'
        Fixture = 'fixtures/basic-maxage.json'
        Expect  = @(
            'SUMMARY: mode=DRY-RUN totalArtifacts=3 deleted=2 retained=1 reclaimedBytes=1300 retainedBytes=200',
            'DELETE: old-build.zip sizeBytes=500 workflow=ci reason="Exceeds max age (7 days): artifact is 26 days old"',
            'DELETE: stale-nightly.zip sizeBytes=800 workflow=nightly reason="Exceeds max age (7 days): artifact is 38 days old"',
            'RETAIN: recent-build.zip sizeBytes=200 workflow=ci',
            'DONE: artifact cleanup completed successfully'
        )
    },
    @{
        Name    = 'keep-latest'
        Fixture = 'fixtures/keep-latest.json'
        Expect  = @(
            'EXECUTED-DELETE: ci-old.zip',
            'SUMMARY: mode=EXECUTE totalArtifacts=3 deleted=1 retained=2 reclaimedBytes=100 retainedBytes=150',
            "DELETE: ci-old.zip sizeBytes=100 workflow=ci reason=`"Exceeds keep-latest-1 for workflow 'ci'`"",
            'RETAIN: ci-new.zip sizeBytes=100 workflow=ci',
            'RETAIN: rel-1.zip sizeBytes=50 workflow=release',
            'DONE: artifact cleanup completed successfully'
        )
    },
    @{
        Name    = 'combined'
        Fixture = 'fixtures/combined.json'
        Expect  = @(
            'SUMMARY: mode=DRY-RUN totalArtifacts=5 deleted=4 retained=1 reclaimedBytes=800 retainedBytes=100',
            "DELETE: a.zip sizeBytes=100 workflow=ci reason=`"Exceeds keep-latest-2 for workflow 'ci'`"",
            "DELETE: b.zip sizeBytes=100 workflow=ci reason=`"Exceeds keep-latest-2 for workflow 'ci'`"",
            'DELETE: c.zip sizeBytes=100 workflow=ci reason="Exceeds max total size (150 bytes): freed 100 bytes"',
            'DELETE: e.zip sizeBytes=500 workflow=release reason="Exceeds max age (60 days): artifact is 177 days old"',
            'RETAIN: d.zip sizeBytes=100 workflow=ci',
            'DONE: artifact cleanup completed successfully'
        )
    }
)

$failures = 0

foreach ($case in $cases) {
    Write-Host "`n=== Running case: $($case.Name) ===" -ForegroundColor Cyan

    # 1. Build an isolated temp git repo.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + $case.Name + "-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null

    foreach ($f in $projectFiles) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $f) -Destination (Join-Path $tmp $f) -Force
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot '.github/workflows/artifact-cleanup-script.yml') `
              -Destination (Join-Path $tmp '.github/workflows/artifact-cleanup-script.yml') -Force
    # The case's fixture becomes the scenario the workflow reads.
    Copy-Item -LiteralPath (Join-Path $repoRoot $case.Fixture) `
              -Destination (Join-Path $tmp 'fixtures/scenario.json') -Force

    Push-Location $tmp
    try {
        git init -q
        git config user.email 'test@example.com'
        git config user.name  'test'
        git add -A
        git commit -qm 'test fixture' | Out-Null

        # 2. Run act, capturing combined stdout+stderr.
        $output = & act push --rm 2>&1 | Out-String
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # 3. Append to the result artifact, delimited.
    Add-Content -LiteralPath $resultFile -Value "================================================================"
    Add-Content -LiteralPath $resultFile -Value "CASE: $($case.Name)   (fixture: $($case.Fixture))"
    Add-Content -LiteralPath $resultFile -Value "act exit code: $exit"
    Add-Content -LiteralPath $resultFile -Value "----------------------------------------------------------------"
    Add-Content -LiteralPath $resultFile -Value $output

    # 4. Assertions.
    $caseOk = $true

    if ($exit -ne 0) {
        Write-Host "  [FAIL] act exit code was $exit (expected 0)" -ForegroundColor Red
        $caseOk = $false
    }

    # Two jobs (test, cleanup) must each report success. act prints "Job succeeded".
    $succeeded = ([regex]::Matches($output, 'Job succeeded')).Count
    if ($succeeded -lt 2) {
        Write-Host "  [FAIL] expected 2 'Job succeeded', found $succeeded" -ForegroundColor Red
        $caseOk = $false
    }

    # Exact-value assertions: every expected line must appear verbatim.
    foreach ($line in $case.Expect) {
        if ($output -notlike ('*' + $line + '*')) {
            Write-Host "  [FAIL] missing expected output line:`n         $line" -ForegroundColor Red
            $caseOk = $false
        }
    }

    if ($caseOk) {
        Write-Host "  [PASS] $($case.Name): exit=0, $succeeded jobs succeeded, all $($case.Expect.Count) expected lines present" -ForegroundColor Green
    } else {
        $failures++
    }

    Add-Content -LiteralPath $resultFile -Value "RESULT: $(if ($caseOk) {'PASS'} else {'FAIL'})"
    Add-Content -LiteralPath $resultFile -Value ""

    # Clean up temp repo.
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n================ SUMMARY ================" -ForegroundColor Cyan
Write-Host "Cases: $($cases.Count)  Failures: $failures"
Write-Host "Full act output saved to: $resultFile"

if ($failures -gt 0) { exit 1 }
Write-Host "ALL ACT TEST CASES PASSED" -ForegroundColor Green
exit 0
