#
# Invoke-ActTestHarness.ps1
#
# Drives the mandatory "prove the workflow actually runs" verification: for
# each fixture scenario below, stages a throwaway git repo containing a copy
# of this project (with that scenario's data swapped into fixtures/ci-run/,
# the directory the workflow's `aggregate` job actually reads), commits it,
# and runs `act push --rm` against the real
# .github/workflows/test-results-aggregator.yml. All output is appended to
# act-result.txt (in this repo, not the temp copy).
#
# This is a harness DRIVER, not a Pester test: `act push` takes 30-90s and
# spins up Docker containers, so it is invoked deliberately (at most once per
# scenario, run manually) rather than from Pester's BeforeAll -- Tests/
# Workflow.Act.Tests.ps1 only ever READS the resulting act-result.txt, so
# re-running the Pester suite never re-triggers act.
#
[CmdletBinding()]
param(
    [string[]]$OnlyCases
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$OutputPath = Join-Path $RepoRoot 'act-result.txt'
$ItemsToCopy = @('TestResultsAggregator.psm1', 'Aggregate-TestResults.ps1', 'Tests', 'fixtures', '.github', '.actrc')

$Cases = @(
    [PSCustomObject]@{
        Name           = 'mixed-matrix-with-failures-and-flaky'
        SourceFixtures = 'fixtures/matrix-build'
    },
    [PSCustomObject]@{
        Name           = 'all-passing-clean-matrix'
        SourceFixtures = 'fixtures/all-passing'
    }
)

if ($OnlyCases) {
    $Cases = $Cases | Where-Object { $_.Name -in $OnlyCases }
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType File -Path $OutputPath -Force | Out-Null
}

foreach ($case in $Cases) {
    Write-Host "=== Running act test case: $($case.Name) ===" -ForegroundColor Cyan

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "act-harness-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        foreach ($item in $ItemsToCopy) {
            $source = Join-Path $RepoRoot $item
            if (Test-Path -LiteralPath $source) {
                Copy-Item -Path $source -Destination $tempDir -Recurse -Force
            }
        }

        # Swap this case's data into fixtures/ci-run -- the directory the
        # workflow's `aggregate` job reads (see RESULTS_PATH env var).
        $ciRunDir = Join-Path $tempDir 'fixtures' 'ci-run'
        Get-ChildItem -Path $ciRunDir -File | Remove-Item -Force
        Copy-Item -Path (Join-Path $RepoRoot $case.SourceFixtures '*') -Destination $ciRunDir -Force

        Push-Location $tempDir
        try {
            git init -q
            git config user.email 'harness@example.com'
            git config user.name 'Act Test Harness'
            git add -A
            git commit -q -m "test case: $($case.Name)"

            # --pull=false: act-ubuntu-pwsh:latest is a local-only image (built via
            # Dockerfile.act, never pushed to a registry). act's default --pull=true
            # tries to force-pull it and fails with a registry auth error.
            $actOutput = & act push --rm --pull=false 2>&1 | Out-String
            $actExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $delimiter = '=' * 80
        $block = @"
$delimiter
TEST CASE: $($case.Name)
SOURCE FIXTURES: $($case.SourceFixtures)
EXIT CODE: $actExitCode
$delimiter
$actOutput

"@
        Add-Content -LiteralPath $OutputPath -Value $block

        Write-Host "=== Case '$($case.Name)' finished with exit code $actExitCode ===" -ForegroundColor Cyan
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Results appended to $OutputPath"
