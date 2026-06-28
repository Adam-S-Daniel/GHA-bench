#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Test Results Aggregator. Parses test result files,
    aggregates them, and writes a markdown job summary + machine-readable metrics.

.DESCRIPTION
    Thin wrapper around the TestResultsAggregator module. Designed to run as a step
    in a GitHub Actions workflow:

        - Markdown is appended to $env:GITHUB_STEP_SUMMARY (the GHA job summary) when set.
        - Markdown is also written to -OutputPath when provided.
        - A KEY=VALUE metrics block is always printed to stdout so CI can assert on
          exact values (TOTAL_TESTS, PASSED, FAILED, SKIPPED, FLAKY_COUNT, ...).

    By default the script exits 0 even when tests in the input failed — aggregating a
    failing matrix is a successful *report*. Pass -FailOnTestFailure to make the step
    exit non-zero when any aggregated test failed (gating behavior).

.PARAMETER Path
    One or more directories, globs, or files containing .xml (JUnit) / .json results.

.PARAMETER OutputPath
    Optional path to also write the rendered markdown summary to.

.PARAMETER ShowSummary
    Also echo the rendered markdown to stdout (useful for `act` log assertions).

.PARAMETER FailOnTestFailure
    Exit with code 1 when the aggregated result is FAILED.

.EXAMPLE
    ./Invoke-Aggregator.ps1 -Path fixtures -ShowSummary
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Path = @('fixtures'),

    [string]$OutputPath,

    [switch]$ShowSummary,

    [switch]$Recurse,

    [switch]$FailOnTestFailure
)

# Fail fast and surface a clean message instead of a raw stack trace.
$ErrorActionPreference = 'Stop'

# Locate the module next to this script so it works regardless of CWD.
$modulePath = Join-Path $PSScriptRoot 'TestResultsAggregator.psm1'
Import-Module $modulePath -Force

try {
    $aggregate = Invoke-TestResultsAggregator -Path $Path -Recurse:$Recurse
}
catch {
    Write-Error "Aggregation failed: $($_.Exception.Message)"
    exit 2
}

$summary  = $aggregate.Summary
$markdown = $aggregate.Markdown

# 1) Write to the GitHub Actions job summary if running in CI.
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown -Encoding utf8
    Write-Host "Wrote job summary to `$GITHUB_STEP_SUMMARY"
}

# 2) Write to an explicit output file if requested.
if ($OutputPath) {
    $markdown | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host "Wrote markdown summary to $OutputPath"
}

# 3) Optionally echo the markdown (handy for asserting on rendered content in CI logs).
if ($ShowSummary) {
    Write-Host '----- MARKDOWN SUMMARY -----'
    Write-Host $markdown
    Write-Host '----- END MARKDOWN -----'
}

# 4) Always print the machine-readable metrics block to stdout.
Write-Host $aggregate.MetricsText

# 5) Exit code policy.
if ($FailOnTestFailure -and $summary.Overall -eq 'FAILED') {
    Write-Host "::error::Test run reported $($summary.Failed) failure(s)."
    exit 1
}

exit 0
