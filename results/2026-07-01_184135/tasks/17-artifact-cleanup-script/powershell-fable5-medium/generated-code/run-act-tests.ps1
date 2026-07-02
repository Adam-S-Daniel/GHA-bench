<#
.SYNOPSIS
    End-to-end test harness: runs every test case through the GitHub Actions
    workflow with act (nektos/act) and asserts on exact expected values.
.DESCRIPTION
    For each test case:
      1. Builds a temp git repo containing the project files plus that case's
         ci/params.json (and fixtures).
      2. Runs `act push --rm` in it (which runs the full Pester suite in the
         pester-tests job, then the cleanup script in the cleanup-plan job).
      3. Appends the act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, every job reported "Job succeeded", and the
         output contains the exact expected RESULT values for that input.
    Also gates on actionlint (exit code 0) before spending any act runs.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot   = $PSScriptRoot
$resultFile = Join-Path $repoRoot 'act-result.txt'
Set-Content -Path $resultFile -Value "act test harness run started $(Get-Date -AsUTC -Format u)`n"

$script:Failures = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:Failures++
    }
}

# --- Gate: actionlint must pass before any act run ---------------------------
Write-Host '== actionlint gate =='
actionlint (Join-Path $repoRoot '.github/workflows/artifact-cleanup-script.yml')
Assert-True ($LASTEXITCODE -eq 0) 'actionlint exits with code 0'
if ($script:Failures) { throw 'actionlint failed; aborting before act runs.' }

# --- Test case definitions ----------------------------------------------------
# Expected values are hand-computed from each fixture + policy set; the
# assertions below require these exact numbers in the act output.
$testCases = @(
    @{
        Name   = 'case1-dry-run-mixed-policies'
        Params = @{
            ArtifactsPath = 'tests/fixtures/sample-artifacts.json'
            MaxAgeDays = 30; KeepLatestPerWorkflow = 1; MaxTotalSizeBytes = 157286400
            ReferenceDate = '2026-07-01T00:00:00Z'; DryRun = $true
        }
        Expect = @(
            'RESULT Mode=DRY-RUN'
            'RESULT TotalArtifacts=5'
            'RESULT DeletedCount=2'
            'RESULT RetainedCount=3'
            'RESULT SpaceReclaimedBytes=136314880'
            'RESULT RetainedSizeBytes=136314880'
            'DELETE build-logs-run1001 reason=MaxAge size=52428800'
            'DELETE build-logs-run1002 reason=MaxTotalSize size=83886080'
        )
    }
    @{
        Name   = 'case2-execute-age-only'
        Params = @{
            ArtifactsPath = 'tests/fixtures/sample-artifacts.json'
            MaxAgeDays = 60
            ReferenceDate = '2026-07-01T00:00:00Z'; DryRun = $false
        }
        Expect = @(
            'RESULT Mode=EXECUTE'
            'RESULT TotalArtifacts=5'
            'RESULT DeletedCount=2'
            'RESULT RetainedCount=3'
            'RESULT SpaceReclaimedBytes=62914560'
            'RESULT RetainedSizeBytes=209715200'
            "Deleted artifact 'build-logs-run1001' (52428800 bytes)"
            "Deleted artifact 'test-results-run1001' (10485760 bytes)"
        )
    }
    @{
        Name   = 'case3-keep-latest-per-workflow'
        Params = @{
            ArtifactsPath = 'tests/fixtures/keep-latest-artifacts.json'
            MaxAgeDays = 10; KeepLatestPerWorkflow = 2
            ReferenceDate = '2026-07-01T00:00:00Z'; DryRun = $true
        }
        Expect = @(
            'RESULT Mode=DRY-RUN'
            'RESULT TotalArtifacts=5'
            'RESULT DeletedCount=2'
            'RESULT RetainedCount=3'
            'RESULT SpaceReclaimedBytes=3000'
            'RESULT RetainedSizeBytes=7500'
            'DELETE nightly-2026-06-01 reason=MaxAge size=1000'
            'DELETE nightly-2026-06-05 reason=MaxAge size=2000'
            'RETAIN docs-2026-06-02 size=500'
        )
    }
)

# --- Run each case through act -------------------------------------------------
foreach ($case in $testCases) {
    Write-Host "== $($case.Name) =="
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "act-cleanup-$($case.Name)"
    if (Test-Path $tempRepo) { Remove-Item $tempRepo -Recurse -Force }
    New-Item -ItemType Directory -Path $tempRepo | Out-Null

    try {
        # Project files this case needs inside its own repo.
        foreach ($item in 'src', 'tests', 'ci', '.github', 'Invoke-ArtifactCleanup.ps1', '.actrc') {
            Copy-Item (Join-Path $repoRoot $item) -Destination $tempRepo -Recurse
        }
        # Swap in this case's parameters (the workflow reads ci/params.json).
        $case.Params | ConvertTo-Json | Set-Content (Join-Path $tempRepo 'ci/params.json')

        git -C $tempRepo init -q -b main
        git -C $tempRepo -c user.email='ci@example.com' -c user.name='ci' add -A
        git -C $tempRepo -c user.email='ci@example.com' -c user.name='ci' commit -q -m 'test case'

        # Run the workflow. --pull=false: the runner image is local-only.
        Push-Location $tempRepo
        try {
            $actOutput = act push --rm --pull=false 2>&1 | Out-String
            $actExit = $LASTEXITCODE
        }
        finally { Pop-Location }

        Add-Content -Path $resultFile -Value @"

================================================================================
TEST CASE: $($case.Name)
PARAMS: $($case.Params | ConvertTo-Json -Compress)
ACT EXIT CODE: $actExit
================================================================================
$actOutput
"@

        Assert-True ($actExit -eq 0) "act exited with code 0 (got $actExit)"
        $succeededJobs = ([regex]::Matches($actOutput, 'Job succeeded')).Count
        Assert-True ($succeededJobs -ge 2) "both jobs report 'Job succeeded' (found $succeededJobs)"
        foreach ($expected in $case.Expect) {
            Assert-True ($actOutput.Contains($expected)) "output contains exact value: $expected"
        }
    }
    finally {
        Remove-Item $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($script:Failures) {
    Write-Host "$script:Failures assertion(s) FAILED. See act-result.txt." -ForegroundColor Red
    exit 1
}
Write-Host 'All act test cases passed.' -ForegroundColor Green
exit 0
