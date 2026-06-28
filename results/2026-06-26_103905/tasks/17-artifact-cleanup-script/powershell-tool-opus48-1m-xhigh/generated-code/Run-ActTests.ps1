#!/usr/bin/env pwsh
<#
.SYNOPSIS
    End-to-end test harness: runs every artifact-cleanup test case through the
    GitHub Actions workflow using nektos/act, plus static workflow-structure
    checks.

.DESCRIPTION
    For each test case this harness:
      1. Creates a throwaway git repo containing the project files and that
         case's scenario fixture (committed as fixtures/scenario.json).
      2. Runs `act push --rm` against the committed workflow.
      3. Appends the full act output to act-result.txt (clearly delimited).
      4. Asserts act exited 0, that every job reports "Job succeeded", and that
         the printed cleanup report matches the EXACT expected values for that
         case's input.

    It also performs workflow-structure tests (actionlint, YAML structure,
    referenced-file existence) before touching act, because those are instant.

    Exit code is 0 only if every assertion in every case passes.
#>
[CmdletBinding()]
param(
    # Skip the (slow) act runs and only do the static structure checks.
    [switch]$StructureOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$ResultFile = Join-Path $RepoRoot 'act-result.txt'
$Workflow = '.github/workflows/artifact-cleanup-script.yml'

# ----------------------------------------------------------------------------
# Tiny assertion helper. Records failures rather than throwing so the harness
# can report every problem in one pass.
# ----------------------------------------------------------------------------
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Checks = 0
function Assert-That {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    $script:Checks++
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:Failures.Add($Message)
    }
}

# Strip ANSI colour codes so log parsing is reliable.
function Remove-Ansi {
    param([string]$Text)
    return ($Text -replace "`e\[[0-9;]*m", '')
}

# Pull a "Key: value" pair out of an (already de-ANSI'd) log body. Matches the
# value through end-of-line so human sizes like "4 MB" are captured intact.
function Get-LogValue {
    param([string]$Log, [string]$Key)
    if ($Log -match "(?m)$([regex]::Escape($Key)):\s*(.+?)\s*$") { return $Matches[1] }
    return $null
}

# ----------------------------------------------------------------------------
# Test-case definitions: each fixture and its known-good expected report values.
# These mirror the exact values asserted by the local CLI-integration Pester
# tests, so a discrepancy here means the pipeline diverged from the library.
# ----------------------------------------------------------------------------
$Cases = @(
    @{
        Name    = 'max-age-only'
        Fixture = 'fixtures/scenario-max-age.json'
        Expect  = @{
            'Mode'                = 'DRY-RUN'
            'TotalArtifacts'      = '3'
            'RetainedCount'       = '1'
            'DeletedCount'        = '2'
            'SpaceReclaimedBytes' = '4194304'
            'SpaceReclaimedHuman' = '4 MB'
            'RetainedSizeBytes'   = '2097152'
        }
    },
    @{
        Name    = 'keep-latest-per-workflow'
        Fixture = 'fixtures/scenario-keep-latest.json'
        Expect  = @{
            'Mode'                = 'DRY-RUN'
            'TotalArtifacts'      = '5'
            'RetainedCount'       = '4'
            'DeletedCount'        = '1'
            'SpaceReclaimedBytes' = '1048576'
            'SpaceReclaimedHuman' = '1 MB'
            'RetainedSizeBytes'   = '3145728'
        }
    },
    @{
        Name    = 'all-policies-combined'
        Fixture = 'fixtures/scenario-combined.json'
        Expect  = @{
            'Mode'                = 'DRY-RUN'
            'TotalArtifacts'      = '6'
            'RetainedCount'       = '2'
            'DeletedCount'        = '4'
            'SpaceReclaimedBytes' = '4194304'
            'SpaceReclaimedHuman' = '4 MB'
            'RetainedSizeBytes'   = '2097152'
        }
    }
)

# ----------------------------------------------------------------------------
# Phase 1 -- static workflow-structure tests (no act required).
# ----------------------------------------------------------------------------
Write-Host "`n=== Workflow structure tests ===" -ForegroundColor Cyan

# actionlint must pass cleanly.
$actionlintOut = & actionlint $Workflow 2>&1 | Out-String
Assert-That ($LASTEXITCODE -eq 0) "actionlint exits 0 (output: '$($actionlintOut.Trim())')"

# Referenced project files must exist.
foreach ($f in 'ArtifactCleanup.psm1', 'Invoke-ArtifactCleanupCli.ps1', 'tests/ArtifactCleanup.Tests.ps1', 'fixtures/scenario.json') {
    Assert-That (Test-Path (Join-Path $RepoRoot $f)) "referenced file exists: $f"
}
foreach ($c in $Cases) {
    Assert-That (Test-Path (Join-Path $RepoRoot $c.Fixture)) "fixture exists: $($c.Fixture)"
}

# Parse the YAML and assert the expected structure.
Import-Module powershell-yaml -ErrorAction Stop
$wf = Get-Content (Join-Path $RepoRoot $Workflow) -Raw | ConvertFrom-Yaml
$triggers = $wf['on']
foreach ($t in 'push', 'pull_request', 'schedule', 'workflow_dispatch') {
    Assert-That ($triggers.Contains($t)) "workflow triggers on '$t'"
}
Assert-That ($wf.permissions.contents -eq 'read') "permissions.contents is 'read'"
Assert-That ($wf.jobs.Contains('unit-tests')) "job 'unit-tests' is defined"
Assert-That ($wf.jobs.Contains('cleanup-plan')) "job 'cleanup-plan' is defined"
Assert-That ("$($wf.jobs['cleanup-plan'].needs)" -match 'unit-tests') "cleanup-plan depends on unit-tests"

# Every job checks out the repo with actions/checkout@v4.
foreach ($jobName in $wf.jobs.Keys) {
    $uses = @($wf.jobs[$jobName].steps | ForEach-Object { $_.uses } | Where-Object { $_ })
    Assert-That ($uses -contains 'actions/checkout@v4') "job '$jobName' uses actions/checkout@v4"
}

# The workflow must actually invoke our CLI script and the Pester tests.
$wfText = Get-Content (Join-Path $RepoRoot $Workflow) -Raw
Assert-That ($wfText -match 'Invoke-ArtifactCleanupCli\.ps1') "workflow references Invoke-ArtifactCleanupCli.ps1"
Assert-That ($wfText -match 'Invoke-Pester') "workflow runs Invoke-Pester"

if ($StructureOnly) {
    Write-Host "`n(StructureOnly) Skipping act runs.`n" -ForegroundColor Yellow
}
else {
    # ------------------------------------------------------------------------
    # Phase 2 -- run every case through act.
    # ------------------------------------------------------------------------
    # Reset the result artifact.
    "Artifact-cleanup act test run`n" | Set-Content -Path $ResultFile -Encoding utf8

    $filesToCopy = 'ArtifactCleanup.psm1', 'Invoke-ArtifactCleanupCli.ps1', '.actrc'
    $dirsToCopy = 'tests', 'fixtures', '.github'

    foreach ($case in $Cases) {
        Write-Host "`n=== act case: $($case.Name) ===" -ForegroundColor Cyan

        # Build a throwaway git repo for this case.
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-case-" + $case.Name + "-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            foreach ($f in $filesToCopy) { Copy-Item (Join-Path $RepoRoot $f) (Join-Path $temp $f) -Force }
            foreach ($d in $dirsToCopy) { Copy-Item (Join-Path $RepoRoot $d) (Join-Path $temp $d) -Recurse -Force }

            # This case's fixture becomes the active scenario the workflow reads.
            Copy-Item (Join-Path $RepoRoot $case.Fixture) (Join-Path $temp 'fixtures/scenario.json') -Force

            Push-Location $temp
            try {
                # Initialise the repo on a branch the workflow's push filter accepts.
                & git -c init.defaultBranch=main init -q
                & git config user.email 'harness@test'
                & git config user.name 'harness'
                & git add -A
                & git commit -q -m "act case $($case.Name)" | Out-Null

                # Run the workflow. --pull=false uses the local custom image from .actrc.
                $actOut = & act push --rm --pull=false -W $Workflow 2>&1 | Out-String
                $actExit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Persist the raw output (clearly delimited) to the required artifact.
            $delim = "`n" + ('=' * 78) + "`nACT CASE: $($case.Name)   (fixture: $($case.Fixture))`nact exit code: $actExit`n" + ('=' * 78)
            Add-Content -Path $ResultFile -Value $delim -Encoding utf8
            Add-Content -Path $ResultFile -Value $actOut -Encoding utf8

            $clean = Remove-Ansi $actOut

            # ---- assertions for this case ----
            Assert-That ($actExit -eq 0) "[$($case.Name)] act exited 0"

            $jobSucceeded = ([regex]::Matches($clean, 'Job succeeded')).Count
            Assert-That ($jobSucceeded -ge 2) "[$($case.Name)] both jobs report 'Job succeeded' (found $jobSucceeded)"

            Assert-That ($clean -match '##CLEANUP-REPORT-BEGIN##') "[$($case.Name)] cleanup report present in pipeline output"

            foreach ($key in $case.Expect.Keys) {
                $expected = $case.Expect[$key]
                $actual = Get-LogValue $clean $key
                Assert-That ($actual -eq $expected) "[$($case.Name)] $key == '$expected' (got '$actual')"
            }
        }
        finally {
            if (Test-Path $temp) { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ----------------------------------------------------------------------------
# Final report.
# ----------------------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Checks run: $script:Checks"
if ($script:Failures.Count -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    if (-not $StructureOnly) { Write-Host "act output saved to: $ResultFile" }
    exit 0
}
else {
    Write-Host "FAILURES ($($script:Failures.Count)):" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
