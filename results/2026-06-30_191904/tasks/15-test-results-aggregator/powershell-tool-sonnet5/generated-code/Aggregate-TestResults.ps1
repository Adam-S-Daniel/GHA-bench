<#
    .SYNOPSIS
    Aggregates JUnit-XML and JSON test result files from a directory
    (simulating the outputs of a CI build matrix), computes totals, detects
    flaky tests, and prints a Markdown summary suitable for a GitHub Actions
    job summary.

    .PARAMETER Path
    Directory containing *.xml (JUnit) and/or *.json test result files. Each
    file is treated as one "run" (e.g. one cell of a build matrix).

    .PARAMETER SummaryPath
    Optional. If set, the Markdown report is also appended to this file
    (typically $env:GITHUB_STEP_SUMMARY when running in GitHub Actions).

    .EXAMPLE
    ./Aggregate-TestResults.ps1 -Path ./test-results -SummaryPath $env:GITHUB_STEP_SUMMARY
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$SummaryPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TestResultsAggregator.psm1') -Force

try {
    $results = Get-AggregatedTestResults -Path $Path
    $summary = Get-TestResultSummary -Results $results
    $flakyTests = Find-FlakyTest -Results $results
    $markdown = New-TestSummaryMarkdown -Summary $summary -FlakyTests $flakyTests

    Write-Output $markdown

    if ($SummaryPath) {
        Add-Content -LiteralPath $SummaryPath -Value $markdown
    }

    if ($summary.Failed -gt 0) {
        Write-Warning "$($summary.Failed) test(s) failed across $($summary.RunCount) run(s)."
    }
}
catch {
    Write-Error "Test results aggregation failed: $($_.Exception.Message)"
    exit 1
}
