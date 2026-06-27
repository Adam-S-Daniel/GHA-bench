#!/usr/bin/env pwsh
# Run-ActTests.ps1
# End-to-end test harness: runs the GitHub Actions workflow through `act` for
# each fixture-driven test case, captures output to act-result.txt, and asserts
# on EXACT expected values (not just "something appeared").
#
# Each case is executed in its own throwaway temp git repo containing the full
# project + that case's fixture copied to fixtures/ci-input.json (the path the
# workflow reads). Run with -Cases to limit which cases execute (keeps the
# number of `act push` invocations within budget).

[CmdletBinding()]
param(
    [string[]] $Cases,                       # subset of case names to run; default = all
    [string]   $ResultFile = (Join-Path $PSScriptRoot 'act-result.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot

# --- Test case definitions ---------------------------------------------------
# Each case names a fixture and the EXACT summary values we expect the workflow
# to print, plus per-artifact assertions.
$allCases = @(
    [pscustomobject]@{
        Name     = 'maxage'
        Fixture  = 'fixtures/basic.json'
        Expect   = @{
            'TotalArtifacts: 3'             = $true
            'Retained: 1'                   = $true
            'Deleted: 2'                    = $true
            'SpaceReclaimed: 1000'          = $true
            'RetainedSize: 100'             = $true
            'DryRun: True'                  = $true
            'DELETE: build-ancient [MaxAge] size=700' = $true
            'DELETE: build-stale [MaxAge] size=300'   = $true
            'RETAIN: build-fresh size=100'  = $true
        }
    },
    [pscustomobject]@{
        Name     = 'combined'
        Fixture  = 'fixtures/combined.json'
        Expect   = @{
            'TotalArtifacts: 4'    = $true
            'Retained: 1'          = $true
            'Deleted: 3'           = $true
            'SpaceReclaimed: 1500' = $true
            'RetainedSize: 700'    = $true
            'DELETE: ancient [MaxAge,KeepLatest] size=100' = $true
            'DELETE: r1-a [KeepLatest] size=700'           = $true
            'DELETE: r1-b [MaxSize] size=700'              = $true
            'RETAIN: r1-c size=700'                        = $true
        }
    },
    [pscustomobject]@{
        Name     = 'keeplatest'
        Fixture  = 'fixtures/keeplatest.json'
        Expect   = @{
            'TotalArtifacts: 3'  = $true
            'Retained: 2'        = $true
            'Deleted: 1'         = $true
            'SpaceReclaimed: 50' = $true
            'RetainedSize: 130'  = $true
            'DELETE: run1-old [KeepLatest] size=50' = $true
            'RETAIN: run1-new size=60'  = $true
            'RETAIN: run2-only size=70' = $true
        }
    }
)

if ($Cases) {
    # Allow comma-separated values in a single arg (pwsh -File quirk).
    $wanted = $Cases | ForEach-Object { $_ -split ',' } | Where-Object { $_ }
    $selected = $allCases | Where-Object { $_.Name -in $wanted }
} else {
    $selected = $allCases
}
if (-not $selected) { throw "No matching test cases for: $($Cases -join ', ')" }

# Files copied into each throwaway repo.
$projectFiles = @(
    'ArtifactCleanup.psm1',
    'Invoke-Cleanup.ps1',
    'ArtifactCleanup.Tests.ps1',
    '.actrc'
)

$failures = @()

foreach ($case in $selected) {
    Write-Host "=== Running case '$($case.Name)' (fixture: $($case.Fixture)) ===" -ForegroundColor Cyan

    # Build an isolated temp git repo for this case.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "act-cleanup-$($case.Name)-$PID"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') | Out-Null

    foreach ($f in $projectFiles) {
        Copy-Item (Join-Path $projectRoot $f) (Join-Path $tmp $f) -Force
    }
    Copy-Item (Join-Path $projectRoot '.github/workflows/artifact-cleanup-script.yml') `
              (Join-Path $tmp '.github/workflows/artifact-cleanup-script.yml') -Force
    # This case's fixture becomes the CI input the workflow reads.
    Copy-Item (Join-Path $projectRoot $case.Fixture) (Join-Path $tmp 'fixtures/ci-input.json') -Force

    # act requires a git repo with at least one commit.
    Push-Location $tmp
    try {
        git init -q
        git config user.email 'ci@example.com'
        git config user.name 'ci'
        git add -A
        git commit -q -m 'test fixture'

        # Run the workflow. --rm cleans up containers; --pull=false uses the
        # locally-built act-ubuntu-pwsh image instead of trying to pull it.
        $output = & act push --rm --pull=false 2>&1 | Out-String
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    # Append delimited output to the shared result file.
    $delim = @(
        '',
        '################################################################################',
        "# TEST CASE: $($case.Name)   fixture=$($case.Fixture)   act_exit=$exit",
        '################################################################################',
        $output
    ) -join [Environment]::NewLine
    Add-Content -LiteralPath $ResultFile -Value $delim

    # --- Assertions ----------------------------------------------------------
    if ($exit -ne 0) {
        $failures += "[$($case.Name)] act exited with $exit (expected 0)"
    }
    if ($output -notmatch 'Job succeeded') {
        $failures += "[$($case.Name)] no 'Job succeeded' in output"
    }
    # Both jobs should report success (one 'Job succeeded' per job).
    $jobSucceeded = ([regex]::Matches($output, 'Job succeeded')).Count
    if ($jobSucceeded -lt 2) {
        $failures += "[$($case.Name)] expected >=2 'Job succeeded' (test + cleanup-plan), got $jobSucceeded"
    }
    foreach ($needle in $case.Expect.Keys) {
        # Literal substring check: -like/-match would treat '[MaxAge]' as a
        # wildcard/regex character class and never match the literal brackets.
        if (-not $output.Contains($needle)) {
            $failures += "[$($case.Name)] missing expected output: '$needle'"
        }
    }

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# --- Report ------------------------------------------------------------------
if ($failures.Count -gt 0) {
    Write-Host "`nFAILURES:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    throw "act test harness: $($failures.Count) assertion(s) failed."
}

Write-Host "`nAll act test cases passed." -ForegroundColor Green
