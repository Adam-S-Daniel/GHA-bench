#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Aggregate test result files and emit a Markdown summary.

.DESCRIPTION
    Reads every JUnit XML (*.xml) and JSON (*.json) test result file in a
    directory (simulating the per-leg outputs of a CI matrix build), computes
    totals (passed/failed/skipped/duration), identifies flaky tests, and renders
    a Markdown summary.

    The summary is:
      * printed to stdout (so it shows up in CI logs),
      * written to -OutputPath if provided, and
      * appended to $env:GITHUB_STEP_SUMMARY if that variable is set (this is how
        GitHub Actions renders a job summary).

    This is a *reporter*: by default it exits 0 even when tests failed, so it can
    publish a summary without failing the job. Pass -FailOnFailure to make it
    return a non-zero exit code when any test failed.

.PARAMETER InputPath
    Directory containing the *.xml / *.json result files to aggregate.

.PARAMETER OutputPath
    Optional path to write the Markdown summary to.

.PARAMETER FailOnFailure
    If set, exit with code 2 when one or more tests failed.

.EXAMPLE
    ./Invoke-Aggregator.ps1 -InputPath ./test-results -OutputPath summary.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $InputPath,

    [string] $OutputPath,

    [switch] $FailOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Import the aggregator module that lives alongside this script.
    $modulePath = Join-Path $PSScriptRoot 'src/TestResultsAggregator.psm1'
    Import-Module $modulePath -Force

    Write-Host "Aggregating test results from: $InputPath"

    $results = @(Import-TestResultDirectory -Path $InputPath)
    $totals  = Measure-TestResults -Results $results
    $markdown = New-MarkdownSummary -Results $results

    # 1. Print to stdout for CI logs.
    Write-Output $markdown

    # 2. Write to the requested output file.
    if ($OutputPath) {
        Set-Content -Path $OutputPath -Value $markdown -Encoding utf8
        Write-Host "Wrote summary to: $OutputPath"
    }

    # 3. Append to the GitHub Actions job summary, if running under Actions.
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $markdown -Encoding utf8
        Write-Host "Appended summary to GITHUB_STEP_SUMMARY."
    }

    # Emit a compact machine-readable status line that CI / test harnesses can
    # grep for without parsing the whole Markdown table.
    Write-Host ("STATUS passed={0} failed={1} skipped={2} total={3} duration={4}" -f `
        $totals.Passed, $totals.Failed, $totals.Skipped, $totals.Total, `
        ([double]$totals.Duration).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture))

    if ($FailOnFailure -and $totals.Failed -gt 0) {
        [Console]::Error.WriteLine("There were $($totals.Failed) failing test(s).")
        exit 2
    }

    exit 0
}
catch {
    # Surface a clear, single-line error message on the error stream and fail
    # with code 1. We force -ErrorAction Continue so that $ErrorActionPreference
    # = 'Stop' does not turn this into a re-thrown terminating error before exit.
    Write-Error "Aggregation failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
