#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Test Results Aggregator. Designed to be called from a
    GitHub Actions workflow step (shell: pwsh).

.DESCRIPTION
    Parses every JUnit XML / JSON test result file under -Path, aggregates them,
    detects flaky tests, and emits a markdown summary three ways:
      1. To stdout (so it is visible in CI logs / captured by `act`).
      2. To -OutputPath, if given (a file you can upload as an artifact).
      3. To $GITHUB_STEP_SUMMARY, if set (renders on the GitHub Actions run page).

    It also prints a single machine-parseable line beginning "AGGREGATE_STATS"
    and one "FLAKY_TEST <key>" line per flaky test, so a CI harness can assert on
    exact values without having to parse markdown tables.

.PARAMETER Path
    File, directory, or glob of test result files. Defaults to "fixtures".

.PARAMETER OutputPath
    Optional path to also write the markdown summary to.

.PARAMETER FailOnTestFailure
    When set, exit non-zero if any aggregated test failed. Off by default so the
    reporting step never fails the build merely because tests failed elsewhere.
#>
[CmdletBinding()]
param(
    [string]$Path = 'fixtures',
    [string]$OutputPath,
    [switch]$FailOnTestFailure
)

# Stop on any error so problems surface immediately with a clear message.
$ErrorActionPreference = 'Stop'

try {
    # Import the module relative to this script so the workflow can invoke it
    # from any working directory.
    $modulePath = Join-Path $PSScriptRoot 'TestResultsAggregator.psm1'
    Import-Module $modulePath -Force

    $aggregate = Get-AggregatedTestResults -Path $Path
    $markdown  = Format-TestResultMarkdown -Aggregate $aggregate
    $summary   = $aggregate.Summary

    # 1. Always print the markdown to stdout.
    Write-Output $markdown

    # 2. Optionally persist to a file (handy as an uploaded artifact).
    if ($OutputPath) {
        $markdown | Set-Content -Path $OutputPath -Encoding utf8
        Write-Output "Wrote summary to $OutputPath"
    }

    # 3. Append to the GitHub Actions job summary when running in CI.
    if ($env:GITHUB_STEP_SUMMARY) {
        $markdown | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
    }

    # Machine-parseable assertion lines (culture-invariant duration).
    $durationStr = $summary.Duration.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture)
    Write-Output ("AGGREGATE_STATS TOTAL={0} PASSED={1} FAILED={2} SKIPPED={3} FLAKY={4} FILES={5} DURATION={6}" -f `
        $summary.Total, $summary.Passed, $summary.Failed, $summary.Skipped, `
        @($aggregate.Flaky).Count, @($aggregate.Files).Count, $durationStr)
    foreach ($f in $aggregate.Flaky) {
        Write-Output ("FLAKY_TEST {0}" -f $f.Key)
    }

    if ($FailOnTestFailure -and $summary.Failed -gt 0) {
        Write-Error "$($summary.Failed) test(s) failed."
        exit 1
    }

    exit 0
}
catch {
    # Graceful, meaningful error output, then a non-zero exit for CI.
    Write-Error "Test results aggregation failed: $($_.Exception.Message)"
    exit 1
}
