#Requires -Version 7.0
<#
    .SYNOPSIS
        Command-line front end for the TestResultsAggregator module.

    .DESCRIPTION
        Imports every JUnit XML / JSON report under -Path, aggregates them into
        combined totals, detects flaky tests, and writes a Markdown summary. It
        is the entry point invoked by the GitHub Actions workflow.

        Output channels:
          * Markdown is appended to -SummaryPath (defaults to the
            $GITHUB_STEP_SUMMARY file GitHub provides), and optionally written
            verbatim to -OutputPath.
          * A handful of stable, machine-readable lines (AGG_TOTALS,
            AGG_FLAKY_COUNT, AGG_FLAKY_TEST) are printed to stdout so CI and the
            test harness can assert on exact values without parsing Markdown.

        By design this script exits 0 even when the aggregated results contain
        failing tests: its job is to *report*, not to gate the build. Pass
        -FailOnTestFailure to make it exit 1 when any test failed.

    .PARAMETER Path
        A directory to scan (recursively) or an explicit list of report files.
        Defaults to the "fixtures" directory next to this script.

    .PARAMETER SummaryPath
        File to append the Markdown summary to. Defaults to $GITHUB_STEP_SUMMARY.

    .PARAMETER OutputPath
        Optional file to write the Markdown summary to verbatim (overwrites).

    .PARAMETER FailOnTestFailure
        When set, exit with code 1 if any aggregated test failed.

    .EXAMPLE
        ./Invoke-Aggregator.ps1 -Path ./fixtures
#>
[CmdletBinding()]
param(
    [string[]] $Path = (Join-Path $PSScriptRoot 'fixtures'),
    [string]   $SummaryPath = $env:GITHUB_STEP_SUMMARY,
    [string]   $OutputPath,
    [switch]   $FailOnTestFailure
)

# Fail fast and loudly on any unhandled error inside the script body.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'src' 'TestResultsAggregator.psm1'
    Import-Module $modulePath -Force

    Write-Host "Aggregating test results from: $($Path -join ', ')"

    $report = Invoke-TestResultAggregation -Path $Path

    $totals = $report.Totals
    $inv    = [System.Globalization.CultureInfo]::InvariantCulture
    $durationText = [string]::Format($inv, '{0:F2}', $totals.Duration)

    # --- Markdown output -----------------------------------------------------
    if ($SummaryPath) {
        # Append (GitHub's $GITHUB_STEP_SUMMARY is append-only by convention).
        Add-Content -LiteralPath $SummaryPath -Value $report.Markdown
        Write-Host "Wrote Markdown summary to: $SummaryPath"
    }
    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $report.Markdown -Encoding utf8
        Write-Host "Wrote Markdown summary to: $OutputPath"
    }

    # --- Machine-readable output for CI / test harness -----------------------
    # These lines have a stable, easily-grepped shape and exact values.
    Write-Host ("AGG_TOTALS passed={0} failed={1} skipped={2} total={3} duration={4} runs={5}" -f `
        $totals.Passed, $totals.Failed, $totals.Skipped, $totals.Total, $durationText, $report.RunCount)
    Write-Host ("AGG_FLAKY_COUNT {0}" -f $report.Flaky.Count)
    foreach ($f in $report.Flaky) {
        Write-Host ("AGG_FLAKY_TEST {0} passed={1} failed={2}" -f $f.Name, $f.PassedCount, $f.FailedCount)
    }

    # Echo the rendered Markdown to the log too, so it is visible in CI output.
    Write-Host '----- BEGIN SUMMARY MARKDOWN -----'
    Write-Host $report.Markdown
    Write-Host '----- END SUMMARY MARKDOWN -----'

    if ($FailOnTestFailure -and $totals.Failed -gt 0) {
        Write-Error "Aggregation found $($totals.Failed) failing test result(s)."
        exit 1
    }

    exit 0
}
catch {
    # Surface a clear, single-line error for CI logs and fail the step.
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
