<#
.SYNOPSIS
    End-to-end test harness: runs every test case through the GitHub Actions
    workflow via act (nektos/act) and asserts exact expected output.

.DESCRIPTION
    For each test case this harness:
      1. Creates a temp git repo containing the project files plus that
         case's fixture data (copied over fixtures/artifacts.json, the
         inventory the workflow reads by default).
      2. Runs `act push --rm` in the temp repo.
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, every job reported "Job succeeded", and the
         output contains the exact known-good values for that case's input
         (per-artifact DELETE/RETAIN lines, counts, reclaimed MB).

    Nothing is tested directly on the host here — all execution happens
    inside the workflow's containers.

.EXAMPLE
    pwsh -NoProfile -File tests/Run-ActTests.ps1
#>
[CmdletBinding()]
param(
    # Where the combined act output is written (required CI artifact).
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot 'act-result.txt' }

# Known-good expectations were derived by hand from each fixture (see the
# "description" field inside the fixture JSON for the arithmetic).
$cases = @(
    [pscustomobject]@{
        Name        = 'case1-dry-run-mixed-policies'
        Fixture     = 'fixtures/case1.json'
        MustContain = @(
            'Mode: DRY RUN'
            'DELETE app-build-ancient (run 100, 200 MB, exceeds max age of 30 days)'
            'DELETE test-logs-old (run 200, 90 MB, evicted to satisfy max total size of 419430400 bytes)'
            'DELETE app-build-prev (run 100, 120 MB, evicted to satisfy max total size of 419430400 bytes)'
            'RETAIN app-build (run 100, 150 MB)'
            'RETAIN test-logs (run 200, 180 MB)'
            'Artifacts retained: 2'
            'Artifacts deleted: 3'
            'Space reclaimed: 410 MB'
            'Retained size: 330 MB'
            'PESTER_TOTAL_PASSED=17'
            'Tests Passed: 17,'
        )
        # A dry run must never report an executed deletion.
        MustNotContain = @('Deleted artifact:')
    }
    [pscustomobject]@{
        Name        = 'case2-execute-age-policy-keep-latest-2'
        Fixture     = 'fixtures/case2.json'
        MustContain = @(
            'Mode: EXECUTE'
            'DELETE nightly-3 (run 500, 70 MB, exceeds max age of 7 days)'
            'DELETE nightly-4 (run 500, 80 MB, exceeds max age of 7 days)'
            'RETAIN release-bundle (run 600, 500 MB)'
            'Deleted artifact: nightly-3'
            'Deleted artifact: nightly-4'
            'Artifacts retained: 3'
            'Artifacts deleted: 2'
            'Space reclaimed: 150 MB'
            'Retained size: 610 MB'
            'PESTER_TOTAL_PASSED=17'
            'Tests Passed: 17,'
        )
        MustNotContain = @()
    }
)

Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Case {
    param([string]$CaseName, [bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  [PASS] $Message"
    }
    else {
        Write-Host "  [FAIL] $Message"
        $failures.Add("${CaseName}: $Message")
    }
}

foreach ($case in $cases) {
    Write-Host "=== Running test case '$($case.Name)' through act ==="

    $work = Join-Path ([System.IO.Path]::GetTempPath()) "act-cleanup-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $work | Out-Null

    try {
        # 1. Temp git repo = project files + this case's fixture data.
        Copy-Item (Join-Path $RepoRoot 'ArtifactCleanup.psm1') $work
        Copy-Item (Join-Path $RepoRoot 'Invoke-ArtifactCleanup.ps1') $work
        Copy-Item (Join-Path $RepoRoot '.actrc') $work
        Copy-Item (Join-Path $RepoRoot 'fixtures') $work -Recurse
        Copy-Item (Join-Path $RepoRoot '.github') $work -Recurse
        New-Item -ItemType Directory -Path (Join-Path $work 'tests') | Out-Null
        Copy-Item (Join-Path $RepoRoot 'tests/ArtifactCleanup.Tests.ps1') (Join-Path $work 'tests')

        # The workflow reads fixtures/artifacts.json; give it this case's data.
        Copy-Item (Join-Path $work $case.Fixture) (Join-Path $work 'fixtures/artifacts.json') -Force

        Push-Location $work
        try {
            git init --quiet --initial-branch=main
            git config user.email 'ci@example.com'
            git config user.name 'CI Harness'
            git add -A
            git commit --quiet -m "test case $($case.Name)"

            # 2. Run the workflow. --pull=false: the runner image is local-only.
            $raw = & act push --rm --pull=false 2>&1 | ForEach-Object { [string]$_ }
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Strip ANSI color sequences so assertions and the saved log are clean.
        $text = ($raw -join "`n") -replace "`e\[[0-9;]*m", ''

        # 3. Append delimited output to act-result.txt.
        Add-Content -LiteralPath $OutputPath -Value @(
            "================================================================"
            "===== TEST CASE: $($case.Name) (fixture: $($case.Fixture))"
            "===== act exit code: $exitCode"
            "================================================================"
            $text
            ""
        )

        # 4. Assertions: exit code, job success, exact expected values.
        Assert-Case $case.Name ($exitCode -eq 0) 'act exited with code 0'

        $succeededJobs = ([regex]::Matches($text, 'Job succeeded')).Count
        Assert-Case $case.Name ($succeededJobs -eq 2) "both jobs report 'Job succeeded' (found $succeededJobs of 2)"
        Assert-Case $case.Name (-not $text.Contains('Job failed')) "no job reports 'Job failed'"

        foreach ($needle in $case.MustContain) {
            Assert-Case $case.Name ($text.Contains($needle)) "output contains exact value: '$needle'"
        }
        foreach ($needle in $case.MustNotContain) {
            Assert-Case $case.Name (-not $text.Contains($needle)) "output does not contain: '$needle'"
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "ACT HARNESS RESULT: FAIL ($($failures.Count) assertion(s) failed)"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "ACT HARNESS RESULT: PASS (all $($cases.Count) cases, output saved to $OutputPath)"
exit 0
