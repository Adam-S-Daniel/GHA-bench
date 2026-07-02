#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end test harness: runs every test case through the GitHub Actions
    workflow via act (nektos/act) and asserts on exact expected output.

.DESCRIPTION
    For each test case the harness:
      1. builds a temp git repo containing the project files plus that
         case's fixture data (the default matrix fixtures, or a swapped-in
         alternative set),
      2. runs `act push --rm` in it,
      3. appends the full act output to ./act-result.txt (delimited),
      4. asserts act exited 0, that both jobs report "Job succeeded", and
         that the log contains the EXACT expected aggregation values for
         that case's input.

    It also runs the required workflow *structure* checks on the host:
    actionlint (assert exit 0) and the Pester workflow-structure tests.

    Exits 0 only if every assertion passes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot   = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'
$workflow   = Join-Path $repoRoot '.github' 'workflows' 'test-results-aggregator.yml'
$failures   = [System.Collections.Generic.List[string]]::new()

# Files copied into every temp repo. fixtures/ is handled per-case.
$projectItems = @('src', 'scripts', 'tests', '.github', '.actrc')

# ---------------------------------------------------------------------------
# Test cases. Expected values are hand-computed from the fixture contents so
# assertions check exact known-good numbers, not just "some output appeared".
# ---------------------------------------------------------------------------
$cases = @(
    @{
        Name        = 'mixed-matrix'
        Description = '3-leg matrix (2x JUnit XML + 1x JSON): 10 tests, failures, a skip, and one flaky test'
        FixtureDir  = Join-Path $repoRoot 'fixtures'   # the default sample matrix
        Expected    = @(
            '| ✅ Passed | 6 |'
            '| ❌ Failed | 3 |'
            '| ⏭️ Skipped | 1 |'
            '| **Total** | **10** |'
            '**Duration:** 4.25s across 3 result file(s)'
            '## ⚠️ Flaky Tests'
            '| Suite.test_flaky | 2 | 1 |'
        )
    }
    @{
        Name        = 'all-pass'
        Description = '2 files, all passing, no flaky tests'
        FixtureDir  = Join-Path $repoRoot 'act-cases' 'all-pass'
        Expected    = @(
            '| ✅ Passed | 3 |'
            '| ❌ Failed | 0 |'
            '| ⏭️ Skipped | 0 |'
            '| **Total** | **3** |'
            '**Duration:** 0.75s across 2 result file(s)'
            '✨ No flaky tests detected.'
        )
    }
)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $failures.Add($Message)
    }
}

# Fresh result artifact for this run.
Set-Content -LiteralPath $resultFile -Value "act test harness run`n" -NoNewline

# ---------------------------------------------------------------------------
# Host-side workflow structure checks (actionlint is not in the act image).
# ---------------------------------------------------------------------------
Write-Host "== Workflow structure checks (host) ==" -ForegroundColor Cyan
& actionlint $workflow
Assert-True ($LASTEXITCODE -eq 0) 'actionlint exits 0 for the workflow'

$pesterResult = Invoke-Pester -Path (Join-Path $repoRoot 'tests' 'Workflow.Tests.ps1') -PassThru -Output None
Assert-True ($pesterResult.FailedCount -eq 0 -and $pesterResult.PassedCount -gt 0) `
    "workflow structure Pester tests pass ($($pesterResult.PassedCount) passed, $($pesterResult.FailedCount) failed)"

# ---------------------------------------------------------------------------
# Run every case through act.
# ---------------------------------------------------------------------------
foreach ($case in $cases) {
    Write-Host "`n== act case: $($case.Name) — $($case.Description) ==" -ForegroundColor Cyan

    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "act-case-$($case.Name)-$(New-Guid)"
    New-Item -ItemType Directory -Path $tempRepo | Out-Null

    try {
        # 1. Assemble the temp repo: project files + this case's fixtures.
        foreach ($item in $projectItems) {
            Copy-Item -Path (Join-Path $repoRoot $item) -Destination $tempRepo -Recurse
        }
        Copy-Item -Path $case.FixtureDir -Destination (Join-Path $tempRepo 'fixtures') -Recurse

        git -C $tempRepo init -q -b main
        git -C $tempRepo add -A
        git -C $tempRepo -c user.email='harness@example.com' -c user.name='act harness' `
            commit -q -m "act case $($case.Name)"

        # 2. Run the workflow through act. --pull=false: the runner image
        # (act-ubuntu-pwsh, mapped in .actrc) exists only locally and act
        # would otherwise force-pull it and die on registry auth.
        Push-Location $tempRepo
        try {
            $actOutput = & act push --rm --pull=false 2>&1 | Out-String
            $actExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # 3. Append the delimited output to the required artifact.
        Add-Content -LiteralPath $resultFile -Value @"

================================================================================
CASE: $($case.Name) — $($case.Description)
EXIT CODE: $actExit
================================================================================
$actOutput
"@

        # 4. Assertions: exit code, job success, exact expected values.
        Assert-True ($actExit -eq 0) "case '$($case.Name)': act exited with code 0"

        foreach ($jobName in 'Pester tests', 'Aggregate test results') {
            Assert-True ($actOutput -match ("(?m)\[Test Results Aggregator/{0}\].*Job succeeded" -f [regex]::Escape($jobName))) `
                "case '$($case.Name)': job '$jobName' shows 'Job succeeded'"
        }

        foreach ($expected in $case.Expected) {
            Assert-True ($actOutput.Contains($expected)) "case '$($case.Name)': output contains exactly '$expected'"
        }
    }
    finally {
        Remove-Item $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "HARNESS FAILED: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "HARNESS PASSED: all act cases and workflow structure checks succeeded." -ForegroundColor Green
Write-Host "Full act output saved to $resultFile"
exit 0
