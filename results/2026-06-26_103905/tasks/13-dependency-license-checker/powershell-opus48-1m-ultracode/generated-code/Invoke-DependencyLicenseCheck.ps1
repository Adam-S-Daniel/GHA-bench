#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry-point for the Dependency License Checker. Used by the GitHub Actions
    workflow and runnable standalone.

.DESCRIPTION
    Parses a dependency manifest, resolves each dependency's license against a local
    license database (the offline stand-in for an external license service),
    classifies each against an allow/deny policy, and prints a compliance report.

    All I/O lives here; the heavy lifting is in DependencyLicenseChecker.psm1, which
    stays pure and unit-tested. The deterministic text output (DEP/RESULT/COMPLIANCE
    lines) is what the CI test harness asserts on.

.PARAMETER ManifestPath
    Path to package.json or requirements.txt. If omitted, the script auto-detects
    one inside -InputDir (requirements.txt first, then package.json).

.PARAMETER PolicyPath
    Path to the allow/deny policy JSON. Defaults to <InputDir>/policy.json.

.PARAMETER LicenseDbPath
    Path to the license database JSON (name -> license). Defaults to
    <InputDir>/licenses.json.

.PARAMETER InputDir
    Directory holding the default inputs. Defaults to 'ci-input'.

.PARAMETER Format
    stdout format: text (default, machine-parseable), markdown, or json.

.PARAMETER SummaryPath
    Where to write the markdown report. Defaults to $env:GITHUB_STEP_SUMMARY when
    set, so the report shows up in the GitHub Actions job summary.

.PARAMETER FailOnViolation
    Exit non-zero when the result is NON-COMPLIANT. Off by default so the report is
    informational and the CI job stays green (the report still states the verdict).

.EXAMPLE
    ./Invoke-DependencyLicenseCheck.ps1 -ManifestPath ci-input/package.json
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$PolicyPath,
    [string]$LicenseDbPath,
    [string]$InputDir = 'ci-input',
    [ValidateSet('text', 'markdown', 'json')]
    [string]$Format = 'text',
    [string]$SummaryPath,
    [switch]$FailOnViolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the library module relative to this script so it works from any CWD.
Import-Module (Join-Path $PSScriptRoot 'DependencyLicenseChecker.psm1') -Force

try {
    # --- Resolve input paths, auto-detecting the manifest when not supplied. ---
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $candidates = @(
            (Join-Path $InputDir 'requirements.txt'),
            (Join-Path $InputDir 'package.json')
        )
        $ManifestPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $ManifestPath) {
            throw "No manifest supplied and none found in '$InputDir' (looked for requirements.txt, package.json)."
        }
    }

    if ([string]::IsNullOrWhiteSpace($PolicyPath))    { $PolicyPath    = Join-Path $InputDir 'policy.json' }
    if ([string]::IsNullOrWhiteSpace($LicenseDbPath)) { $LicenseDbPath = Join-Path $InputDir 'licenses.json' }

    # --- Load inputs (each function throws a clear error if a file is missing). ---
    $dependencies = Get-DependencyList -ManifestPath $ManifestPath
    $policy        = Read-LicensePolicy -PolicyPath $PolicyPath
    $database      = Read-LicenseDatabase -Path $LicenseDbPath

    # --- Build the report + summary. ---
    $report  = Get-ComplianceReport -Dependencies $dependencies -Policy $policy -Database $database
    $summary = Get-ComplianceSummary -Report $report

    # --- Emit the requested format to stdout (text drives CI assertions). ---
    Write-Output (Format-ComplianceReport -Report $report -Summary $summary -Format $Format)

    # --- Always publish a markdown report to the job step summary when possible. ---
    $effectiveSummaryPath = $SummaryPath
    if ([string]::IsNullOrWhiteSpace($effectiveSummaryPath)) { $effectiveSummaryPath = $env:GITHUB_STEP_SUMMARY }
    if (-not [string]::IsNullOrWhiteSpace($effectiveSummaryPath)) {
        try {
            $markdown = Format-ComplianceReport -Report $report -Summary $summary -Format markdown
            Add-Content -LiteralPath $effectiveSummaryPath -Value $markdown -Encoding utf8
        }
        catch {
            # A summary-write failure must never fail the job; surface it as a warning.
            Write-Warning "Could not write job summary to '$effectiveSummaryPath': $($_.Exception.Message)"
        }
    }

    # --- Exit code policy. ---
    if ($FailOnViolation -and -not $summary.Compliant) {
        Write-Error "Compliance check failed: $($summary.Denied) denied, $($summary.Unknown) unknown license(s)."
        exit 1
    }

    exit 0
}
catch {
    # Graceful failure with a meaningful, single-line message.
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 2
}
