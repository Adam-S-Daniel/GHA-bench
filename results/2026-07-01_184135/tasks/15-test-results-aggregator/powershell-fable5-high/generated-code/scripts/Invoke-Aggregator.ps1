#Requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point: aggregates a directory of test result files (JUnit XML
    and JSON) and emits a markdown summary.

.DESCRIPTION
    Designed for GitHub Actions:
      * writes the markdown summary to -OutputPath,
      * prints it to stdout (so CI logs / act output contain the exact values),
      * appends it to $GITHUB_STEP_SUMMARY when running inside Actions.

    The script is a *reporter*: failed tests in the input do not fail the
    step (pass -FailOnTestFailures to change that). Genuine errors — missing
    directory, malformed files — exit with code 1 and a clear message.

.EXAMPLE
    ./scripts/Invoke-Aggregator.ps1 -InputPath fixtures -OutputPath summary.md
#>
[CmdletBinding()]
param(
    # Directory containing the result files from all matrix legs.
    [Parameter(Mandatory)]
    [string]$InputPath,

    # Where to write the markdown summary.
    [string]$OutputPath = 'summary.md',

    # Opt-in: exit 1 when any aggregated test failed.
    [switch]$FailOnTestFailures
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'src' 'TestResultsAggregator.psm1') -Force

try {
    $results  = @(Import-TestResultDirectory -Path $InputPath)
    $summary  = Get-TestResultSummary -Results $results
    $markdown = New-MarkdownSummary -Summary $summary

    Set-Content -LiteralPath $OutputPath -Value $markdown -NoNewline

    # Surface the summary in the job log so it is machine-checkable from act.
    Write-Host $markdown

    # And publish it to the GitHub Actions job summary when available.
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown
    }

    if ($FailOnTestFailures -and $summary.Failed -gt 0) {
        Write-Error "Aggregation found $($summary.Failed) failed test(s)."
        exit 1
    }
    exit 0
}
catch {
    Write-Error "Test results aggregation failed: $($_.Exception.Message)"
    exit 1
}
