#!/usr/bin/env pwsh
#
# Invoke-ActHarness.ps1
#
# Drives the Environment Matrix Generator workflow through `act` (nektos/act)
# for each test-case fixture. For every case it:
#
#   1. Builds a throwaway git repo in a temp dir containing the project files
#      plus that case's fixture copied to `matrix-config.json` (the path the
#      workflow's MATRIX_CONFIG env var points at).
#   2. Runs `act push --rm`, capturing combined stdout+stderr and the exit code.
#   3. Writes the raw output to `act-out-<case>.txt` and records a structured
#      summary (exit code + full output) in `act-results.json`.
#   4. Rebuilds the consolidated `act-result.txt` artifact from every case
#      captured so far, clearly delimited.
#
# Running act is expensive (~30-90s/case), so results are cached: a case is
# only re-run when it has no cached result, unless -Force is supplied. This lets
# the Pester harness (Workflow.Tests.ps1) consume cached results without paying
# the act cost on every assertion run.
#
# Usage:
#   ./Invoke-ActHarness.ps1                 # run any not-yet-cached cases
#   ./Invoke-ActHarness.ps1 -Cases basic    # run just the 'basic' case
#   ./Invoke-ActHarness.ps1 -Force          # re-run every case from scratch

[CmdletBinding()]
param(
    # Fixture basenames (without .json) to run. Defaults to all fixtures.
    [string[]] $Cases,
    # Re-run cases even when a cached result already exists.
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root        = $PSScriptRoot
$fixturesDir = Join-Path $root 'fixtures'
$resultsJson = Join-Path $root 'act-results.json'
$artifact    = Join-Path $root 'act-result.txt'

# Stable, intentional ordering of the test cases so the artifact reads top-down.
$allCases = @('basic', 'exclude-include', 'include-new')

if (-not $Cases) { $Cases = $allCases }

# Project files that must travel into each throwaway repo for the workflow to run.
$projectFiles = @(
    'BuildMatrix.psm1',
    'Generate-Matrix.ps1',
    'BuildMatrix.Tests.ps1',
    '.actrc'
)

# Load any previously cached results so staged runs accumulate.
$results = [ordered]@{}
if (Test-Path $resultsJson) {
    $loaded = Get-Content -Raw $resultsJson | ConvertFrom-Json
    foreach ($p in $loaded.PSObject.Properties) {
        $results[$p.Name] = $p.Value
    }
}

function Invoke-OneCase {
    param([string] $Case)

    $fixture = Join-Path $fixturesDir "$Case.json"
    if (-not (Test-Path $fixture)) {
        throw "Fixture not found for case '$Case': $fixture"
    }

    # Fresh temp repo for this case.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-$Case-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        # Copy the project files and the workflow.
        foreach ($f in $projectFiles) {
            Copy-Item -Path (Join-Path $root $f) -Destination (Join-Path $tmp $f) -Force
        }
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        Copy-Item -Path (Join-Path $root '.github/workflows/environment-matrix-generator.yml') `
                  -Destination (Join-Path $tmp '.github/workflows/environment-matrix-generator.yml') -Force

        # This case's fixture becomes the config the workflow reads.
        Copy-Item -Path $fixture -Destination (Join-Path $tmp 'matrix-config.json') -Force

        Push-Location $tmp
        try {
            # act push requires a git repo with at least one commit.
            git init -q 2>&1 | Out-Null
            git config user.email 'harness@example.com' 2>&1 | Out-Null
            git config user.name  'act harness'         2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m "case $Case" 2>&1 | Out-Null

            Write-Host "==> Running act for case '$Case' ..."
            # Combined stdout+stderr; do not let a non-zero act exit abort the script.
            # --pull=false: the ubuntu-latest mapping points at a LOCAL-only image
            # (act-ubuntu-pwsh:latest); without this act force-pulls it from a
            # registry and fails auth. The image is pre-built in this environment.
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Persist this case's raw output next to the project for inspection.
        $perCase = Join-Path $root "act-out-$Case.txt"
        Set-Content -Path $perCase -Value $output -Encoding utf8

        return [ordered]@{
            case     = $Case
            exitCode = $exit
            output   = $output
        }
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    }
}

foreach ($case in $Cases) {
    if (-not $Force -and $results.Contains($case)) {
        Write-Host "==> Skipping cached case '$case' (use -Force to re-run)."
        continue
    }
    $results[$case] = Invoke-OneCase -Case $case
    Write-Host "    case '$case' finished with exit code $($results[$case].exitCode)"
}

# Save the structured cache.
$results | ConvertTo-Json -Depth 6 | Set-Content -Path $resultsJson -Encoding utf8

# Rebuild the consolidated artifact in canonical case order, with clear delimiters.
$sb = [System.Text.StringBuilder]::new()
foreach ($case in $allCases) {
    if (-not $results.Contains($case)) { continue }
    $r = $results[$case]
    [void]$sb.AppendLine('=' * 78)
    [void]$sb.AppendLine("TEST CASE: $case   (act exit code: $($r.exitCode))")
    [void]$sb.AppendLine("FIXTURE:   fixtures/$case.json")
    [void]$sb.AppendLine('=' * 78)
    [void]$sb.AppendLine($r.output)
    [void]$sb.AppendLine()
}
Set-Content -Path $artifact -Value $sb.ToString() -Encoding utf8

Write-Host "==> Wrote $artifact and $resultsJson"
foreach ($case in $allCases) {
    if ($results.Contains($case)) {
        Write-Host ("    {0,-16} exit={1}" -f $case, $results[$case].exitCode)
    }
}
