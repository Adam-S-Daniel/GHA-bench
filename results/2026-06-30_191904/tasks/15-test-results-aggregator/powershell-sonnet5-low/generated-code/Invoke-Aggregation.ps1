<#
.SYNOPSIS
    Aggregates JUnit XML and JSON test result fixtures into a single markdown
    summary, writing it to $env:GITHUB_STEP_SUMMARY when running in CI.
#>
param(
    [string] $FixturesPath = (Join-Path $PSScriptRoot 'fixtures')
)

Import-Module (Join-Path $PSScriptRoot 'src' 'Aggregator.psm1') -Force

$allResults = @()
$allResults += Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run1.xml') -RunName 'run1'
$allResults += Get-JUnitTestResults -Path (Join-Path $FixturesPath 'junit-run2.xml') -RunName 'run2'
$allResults += Get-JsonTestResults -Path (Join-Path $FixturesPath 'results-run3.json') -RunName 'run3'

$merged = Merge-TestResults -Results $allResults
$summary = New-MarkdownSummary -Aggregated $merged

Write-Output $summary

if ($env:GITHUB_STEP_SUMMARY) {
    $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

if ($merged.TotalFailed -gt 0) {
    Write-Warning "$($merged.TotalFailed) test(s) failed across the aggregated runs."
}
