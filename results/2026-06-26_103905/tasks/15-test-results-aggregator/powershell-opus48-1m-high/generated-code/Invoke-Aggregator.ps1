#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point for the Test Results Aggregator.
.DESCRIPTION
    Loads every supported test-result file under -Path (a directory or single
    file), aggregates the results across runs (a CI matrix), computes totals,
    detects flaky tests, and renders a markdown summary.

    The markdown is always written to stdout. When the GITHUB_STEP_SUMMARY
    environment variable is set (as it is inside GitHub Actions / act), the
    summary is also appended to that file so it shows up on the job summary page.
.PARAMETER Path
    Directory containing .xml / .json result files, or a single result file.
.PARAMETER OutFile
    Optional path to also write the markdown summary to.
.EXAMPLE
    ./Invoke-Aggregator.ps1 -Path ./fixtures
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$OutFile,

    # Opt-in build gate: exit non-zero when any test failed. Off by default so
    # the aggregator behaves as a pure reporter (the common CI summary use case).
    [switch]$FailOnFailure
)

# Fail fast and loud — meaningful errors are a requirement.
$ErrorActionPreference = 'Stop'

try {
    # Import the module that lives next to this script.
    $modulePath = Join-Path $PSScriptRoot 'TestResultsAggregator.psm1'
    Import-Module $modulePath -Force

    $records   = Import-TestResults -Path $Path
    $aggregate = Get-TestAggregate -Records $records
    $markdown  = New-MarkdownSummary -Aggregate $aggregate

    # 1) Always emit to stdout (this is what the act harness asserts against).
    Write-Output $markdown

    # 2) Append to the GitHub Actions job summary when running in CI.
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown
    }

    # 3) Optional explicit output file.
    if ($OutFile) {
        Set-Content -LiteralPath $OutFile -Value $markdown -Encoding utf8
    }

    # Optionally surface failures as a non-zero exit so CI can gate on red
    # builds. Off by default: the aggregator is a reporter, not the gate.
    if ($FailOnFailure -and $aggregate.Failed -gt 0) {
        Write-Error "Test run contains $($aggregate.Failed) failure(s)." -ErrorAction Continue
        exit 1
    }

    exit 0
}
catch {
    # Use -ErrorAction Continue so this write does not itself re-throw under the
    # script's 'Stop' preference, letting the explicit exit code take effect.
    Write-Error "Aggregation failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 2
}
