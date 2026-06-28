<#
.SYNOPSIS
    CLI entry point: aggregate test result files and emit a markdown summary.

.DESCRIPTION
    Thin wrapper around the TestResultsAggregator module. Designed to run inside
    a GitHub Actions step. It:
      - parses every .xml / .json result file under -InputPath,
      - writes the markdown summary to -OutputPath,
      - appends the summary to $GITHUB_STEP_SUMMARY when running in Actions,
      - prints the key totals to stdout (so `act` output can be asserted on),
      - exits non-zero when any test failed (so CI reflects the result).

.PARAMETER InputPath
    Directory (searched recursively) or single result file. Default: ./fixtures
.PARAMETER OutputPath
    Where to write the markdown summary. Default: ./test-summary.md
.PARAMETER FailOnTestFailure
    When set, exit code 1 if any aggregated test failed. Flaky-only does not fail.
#>
[CmdletBinding()]
param(
    [string]$InputPath  = './fixtures',
    [string]$OutputPath = './test-summary.md',
    [switch]$FailOnTestFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module relative to this script so paths work regardless of CWD.
Import-Module (Join-Path $PSScriptRoot 'src/TestResultsAggregator.psm1') -Force

try {
    $agg = Invoke-TestResultsAggregation -InputPath $InputPath -OutputPath $OutputPath
} catch {
    Write-Error "Aggregation failed: $($_.Exception.Message)"
    exit 2
}

# Machine-parseable lines for the act harness to assert exact values against.
Write-Host "AGG_TOTAL=$($agg.Total)"
Write-Host "AGG_PASSED=$($agg.Passed)"
Write-Host "AGG_FAILED=$($agg.Failed)"
Write-Host "AGG_SKIPPED=$($agg.Skipped)"
Write-Host "AGG_FLAKY_COUNT=$($agg.Flaky.Count)"
Write-Host "AGG_FLAKY=$($agg.Flaky -join ',')"

# Publish to the GitHub Actions job summary when available.
if ($env:GITHUB_STEP_SUMMARY) {
    Get-Content -LiteralPath $OutputPath -Raw | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
    Write-Host "Wrote job summary to GITHUB_STEP_SUMMARY"
}

Write-Host "Summary written to $OutputPath"

if ($FailOnTestFailure -and $agg.Failed -gt 0) {
    Write-Error "There were $($agg.Failed) failing test result(s)."
    exit 1
}

exit 0
