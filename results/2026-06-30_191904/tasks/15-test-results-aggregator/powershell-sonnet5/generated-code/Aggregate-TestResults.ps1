#
# Aggregate-TestResults.ps1
#
# CLI entry point: reads every JUnit XML / JSON test result file in -Path,
# aggregates totals across them (simulating a matrix build), detects flaky
# tests, and writes a Markdown summary suitable for a GitHub Actions job
# summary. By default it also writes the summary to $env:GITHUB_STEP_SUMMARY
# when that environment variable is set (i.e. when running inside Actions).
#
[CmdletBinding()]
param(
    # Directory containing *.xml (JUnit) and/or *.json test result files.
    [Parameter(Mandatory)]
    [string]$Path,

    # Where to write the Markdown summary. Defaults to stdout only.
    [string]$OutputPath,

    # When set, the script exits with a non-zero code if any test failed,
    # so a CI job can be made to fail based on aggregated results.
    [switch]$FailOnTestFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TestResultsAggregator.psm1') -Force

try {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Test results directory '$Path' not found."
    }

    $resultFiles = @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in '.xml', '.json' })

    if ($resultFiles.Count -eq 0) {
        throw "No .xml or .json test result files found in '$Path'."
    }

    $parsed = $resultFiles | ForEach-Object { Get-TestResultFile -Path $_.FullName }
    $aggregate = Merge-TestResults -Results $parsed
    # @(...) is required: when Find-FlakyTests writes zero objects to the
    # pipeline, a plain assignment unrolls that to $null instead of an empty
    # array, which then fails to bind to New-TestResultsMarkdownSummary's
    # mandatory [object[]] -FlakyTests parameter.
    $flaky = @(Find-FlakyTests -Results $parsed)
    $markdown = New-TestResultsMarkdownSummary -Aggregate $aggregate -FlakyTests $flaky

    Write-Output $markdown

    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $markdown
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown
    }

    if ($FailOnTestFailure -and $aggregate.Summary.Failed -gt 0) {
        Write-Error "$($aggregate.Summary.Failed) test(s) failed." -ErrorAction Continue
        exit 1
    }

    exit 0
} catch {
    $ErrorActionPreference = 'Continue'
    Write-Error $_.Exception.Message
    exit 1
}
