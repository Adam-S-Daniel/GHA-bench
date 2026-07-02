#Requires -Version 7.0
<#
.SYNOPSIS
    Aggregates test result files (JUnit XML + JSON) into a markdown summary.

.DESCRIPTION
    Entry point used by the CI workflow. Finds *.xml / *.json result files
    under -Path (each file simulating one matrix-build run), aggregates
    them, prints the markdown summary to stdout and writes it to
    -OutputPath so the workflow can append it to $GITHUB_STEP_SUMMARY.

.PARAMETER Path
    Directory containing test result files (searched recursively).

.PARAMETER OutputPath
    File to write the markdown summary to.

.PARAMETER FailOnTestFailure
    Exit with code 1 when any aggregated test failed. Off by default so
    the summary step itself does not fail the pipeline unless asked to.

.EXAMPLE
    ./Invoke-TestResultsAggregator.ps1 -Path fixtures -OutputPath summary.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [switch]$FailOnTestFailure
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TestResultsAggregator.psm1') -Force

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Input path not found: '$Path'"
}

# Each *.xml / *.json file represents one run of a matrix build.
$files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Include *.xml, *.json |
    Sort-Object FullName)

if ($files.Count -eq 0) {
    throw "No test result files (*.xml, *.json) found under '$Path'"
}

Write-Host "Aggregating $($files.Count) result file(s) from '$Path'..."

$results = @(foreach ($file in $files) { Import-TestResultFile -Path $file.FullName })
$aggregate = Get-AggregatedResults -Results $results
$markdown = New-MarkdownSummary -Aggregate $aggregate -FileCount $files.Count

Set-Content -LiteralPath $OutputPath -Value $markdown -Encoding utf8
Write-Host "Summary written to '$OutputPath'"
Write-Host ''
Write-Host $markdown

if ($FailOnTestFailure -and $aggregate.Failed -gt 0) {
    Write-Error "Aggregated results contain $($aggregate.Failed) failed test(s)." -ErrorAction Continue
    exit 1
}
