#requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point for the Test Results Aggregator.

.DESCRIPTION
    Loads every JUnit XML / JSON test result file found under -Path, aggregates
    them, and renders a markdown summary. The markdown is:
      * written to stdout (so it appears in CI logs),
      * appended to the GitHub Actions job summary ($GITHUB_STEP_SUMMARY) when
        running inside Actions or `act`,
      * optionally written to -OutFile.

    It also emits machine-readable "[SUMMARY]" / "[FLAKY]" lines that downstream
    steps and the test harness can assert against, and publishes totals as
    GitHub Actions step outputs ($GITHUB_OUTPUT) for dependent jobs.

    This is a *reporting* tool: it always exits 0 on successful aggregation so
    it never fails the build itself. Gating on failures/flakiness is the job of
    the test step (or the downstream report job). A parse/usage error exits 2.

.PARAMETER Path
    One or more files, directories, or glob patterns containing result files.
    Defaults to the 'fixtures' directory.

.PARAMETER OutFile
    Optional path to also write the markdown summary to.

.PARAMETER Quiet
    Suppress the machine-readable [SUMMARY]/[FLAKY] lines (markdown still emitted).

.EXAMPLE
    ./Invoke-Aggregator.ps1 -Path fixtures -OutFile summary.md
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Path = @('fixtures'),

    [string]$OutFile,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the library that lives next to this script.
. (Join-Path $PSScriptRoot 'TestResultsAggregator.ps1')

try {
    $results = Import-TestResultSet -Path $Path
}
catch {
    # Write to stderr and exit non-zero so CI surfaces the problem clearly.
    [Console]::Error.WriteLine("Aggregation failed: $($_.Exception.Message)")
    exit 2
}

$summary  = Get-AggregateSummary -Result $results
$markdown = Format-MarkdownSummary -Summary $summary

# 1. Markdown summary -> stdout (primary, human-readable output).
Write-Output $markdown

# 2. Markdown summary -> GitHub Actions job summary, when available.
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown
}

# 3. Markdown summary -> file, when requested.
if ($OutFile) {
    Set-Content -LiteralPath $OutFile -Value $markdown -Encoding utf8
    Write-Output "Wrote markdown summary to '$OutFile'."
}

# 4. Machine-readable lines for assertions (single-line, easy to grep).
if (-not $Quiet) {
    Write-Output ('[SUMMARY] passed={0} failed={1} skipped={2} total={3} runs={4} duration={5:F2} passrate={6:F1}' -f `
            $summary.Passed, $summary.Failed, $summary.Skipped, $summary.Total, $summary.Runs, $summary.Duration, $summary.PassRate)

    $flaky = @($summary.Flaky)
    Write-Output ('[FLAKY] count={0}' -f $flaky.Count)
    foreach ($f in $flaky) {
        Write-Output ('[FLAKY] {0} passed={1} failed={2} runs={3}' -f $f.FullName, $f.Passed, $f.Failed, $f.Runs)
    }
}

# 5. Publish totals as step outputs so dependent jobs can consume them.
if ($env:GITHUB_OUTPUT) {
    $flakyCount = @($summary.Flaky).Count
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "passed=$($summary.Passed)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "failed=$($summary.Failed)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "skipped=$($summary.Skipped)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "total=$($summary.Total)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "flaky=$flakyCount"
}

# Reporting tool: succeed even when tests failed/were flaky.
exit 0
