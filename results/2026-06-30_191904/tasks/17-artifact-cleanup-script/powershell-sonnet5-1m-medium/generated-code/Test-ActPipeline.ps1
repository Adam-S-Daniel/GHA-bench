#requires -Version 7.0
<#
    .SYNOPSIS
    Host-side test harness: runs the artifact-cleanup-script workflow through
    `act push`, saves the full output to act-result.txt, and asserts on the
    exact expected values for each fixture-driven test case baked into the
    workflow (see .github/workflows/artifact-cleanup-script.yml).

    This is the "all tests run through the pipeline" harness -- it does not
    call Invoke-ArtifactCleanup.ps1 directly; every assertion is made against
    what actually came out of the `act` run of the real GitHub Actions
    workflow.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot
Push-Location $repoRoot
try {
    $resultPath = Join-Path $repoRoot 'act-result.txt'

    Write-Output 'Running: act push --rm --pull=false'
    $actOutput = & act push --rm --pull=false 2>&1
    $actExitCode = $LASTEXITCODE

    $header = @(
        '=' * 80
        "act push --rm --pull=false"
        "Exit code: $actExitCode"
        "Captured: $(Get-Date -AsUTC -Format 'o')"
        '=' * 80
    ) -join "`n"

    ($header + "`n" + ($actOutput -join "`n") + "`n") | Set-Content -Path $resultPath -Encoding utf8

    Write-Output "Saved act output to $resultPath"

    # --- Assertions -------------------------------------------------------
    $failures = [System.Collections.Generic.List[string]]::new()

    if ($actExitCode -ne 0) {
        $failures.Add("act exited with code $actExitCode, expected 0")
    }

    $outputText = $actOutput -join "`n"

    $jobSucceededCount = ([regex]::Matches($outputText, 'Job succeeded')).Count
    if ($jobSucceededCount -ne 2) {
        $failures.Add("expected 2 'Job succeeded' lines (unit-tests, cleanup-plan), found $jobSucceededCount")
    }

    # Test case: basic mixed policies (age + keep-latest-N + size budget combined)
    if ($outputText -notmatch '(?s)=== TESTCASE basic ===.*?TotalArtifacts=5.*?RetainedCount=3.*?DeletedCount=2.*?SpaceReclaimedBytes=5000000.*?SpaceRetainedBytes=2000000.*?DryRun=False') {
        $failures.Add("TESTCASE basic did not produce the expected exact summary (TotalArtifacts=5, RetainedCount=3, DeletedCount=2, SpaceReclaimedBytes=5000000, SpaceRetainedBytes=2000000, DryRun=False)")
    }

    # Test case: dry run (same plan, nothing actually deleted)
    if ($outputText -notmatch '(?s)=== TESTCASE dryrun ===.*?TotalArtifacts=5.*?RetainedCount=3.*?DeletedCount=2.*?SpaceReclaimedBytes=5000000.*?SpaceRetainedBytes=2000000.*?DryRun=True') {
        $failures.Add("TESTCASE dryrun did not produce the expected exact summary (DryRun=True, otherwise identical to TESTCASE basic)")
    }

    # Test case: keep-latest-N-only (single workflow, KeepLatestN=1)
    if ($outputText -notmatch '(?s)=== TESTCASE keeplatest ===.*?TotalArtifacts=3.*?RetainedCount=1.*?DeletedCount=2.*?SpaceReclaimedBytes=500.*?SpaceRetainedBytes=100.*?DryRun=False') {
        $failures.Add("TESTCASE keeplatest did not produce the expected exact summary (TotalArtifacts=3, RetainedCount=1, DeletedCount=2, SpaceReclaimedBytes=500, SpaceRetainedBytes=100, DryRun=False)")
    }

    # Pester counts asserted exactly: 10 module tests, 8 passed + 1 skipped
    # (actionlint-skip only fires when actionlint is missing on the host --
    # it is present in the act container, so expect 9 passed there) for the
    # workflow-structure suite.
    if ($outputText -notmatch 'PESTER_ARTIFACT_TESTS_PASSED=10') {
        $failures.Add("expected exactly PESTER_ARTIFACT_TESTS_PASSED=10")
    }
    if ($outputText -notmatch 'PESTER_WORKFLOW_TESTS_PASSED=9' -and $outputText -notmatch 'PESTER_WORKFLOW_TESTS_PASSED=8') {
        $failures.Add("expected PESTER_WORKFLOW_TESTS_PASSED=9 (actionlint present) or =8 (actionlint skipped)")
    }

    if ($failures.Count -gt 0) {
        Write-Output ''
        Write-Output 'ASSERTION FAILURES:'
        foreach ($f in $failures) { Write-Output " - $f" }
        ("`nASSERTION FAILURES:`n" + ($failures -join "`n")) | Add-Content -Path $resultPath -Encoding utf8
        throw "$($failures.Count) assertion(s) failed against the act output. See $resultPath."
    }

    Write-Output ''
    Write-Output 'All act pipeline assertions passed:'
    Write-Output ' - act exited 0'
    Write-Output ' - both jobs reported Job succeeded'
    Write-Output ' - TESTCASE basic / dryrun / keeplatest all matched exact expected values'
    Write-Output ' - Pester test counts matched exactly'
    ("`nALL ASSERTIONS PASSED`n") | Add-Content -Path $resultPath -Encoding utf8
} finally {
    Pop-Location
}
