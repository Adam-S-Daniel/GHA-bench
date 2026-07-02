<#
.SYNOPSIS
    CLI entry point for the dependency license compliance checker.

.DESCRIPTION
    Parses a dependency manifest, classifies every dependency's license
    against the configured allow/deny lists (license lookups are served by a
    mock JSON registry database), and prints a compliance report.

    Output contract (asserted by CI):
      RESULT|<name>|<version>|<license>|<status>   one line per dependency
      SUMMARY|approved=<n>|denied=<n>|unknown=<n>  exact totals

    Exit codes: 0 = success, 1 = error, 2 = denied licenses found while
    -FailOnDenied is set.

.EXAMPLE
    ./check-licenses.ps1 -ManifestPath fixtures/package.json `
        -ConfigPath fixtures/license-config.json `
        -LicenseDatabasePath fixtures/mock-license-db.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LicenseDatabasePath,

    # Optional path to also write the report as JSON.
    [string]$OutputPath,

    # Turn denied licenses into a failing exit code (for gating pipelines).
    [switch]$FailOnDenied
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'DependencyLicenseChecker.psm1') -Force

    $report = @(Invoke-LicenseCheck -ManifestPath $ManifestPath -ConfigPath $ConfigPath -LicenseDatabasePath $LicenseDatabasePath)

    Write-Host "Dependency license compliance report for '$ManifestPath'"
    foreach ($entry in $report) {
        Write-Host "RESULT|$($entry.Name)|$($entry.Version)|$($entry.License)|$($entry.Status)"
    }

    # Exact per-status totals; keys are emitted in a fixed order so CI can
    # assert the whole line verbatim.
    $counts = @{ approved = 0; denied = 0; unknown = 0 }
    foreach ($entry in $report) { $counts[$entry.Status]++ }
    Write-Host "SUMMARY|approved=$($counts.approved)|denied=$($counts.denied)|unknown=$($counts.unknown)"

    if ($OutputPath) {
        ConvertTo-Json @($report) -Depth 4 | Set-Content -Path $OutputPath -Encoding utf8
        Write-Host "Report written to '$OutputPath'"
    }

    if ($FailOnDenied -and $counts.denied -gt 0) {
        Write-Error -ErrorAction Continue "Found $($counts.denied) dependency(ies) with denied licenses."
        exit 2
    }
    exit 0
}
catch {
    # Surface a single meaningful error line and a non-zero exit code.
    Write-Error -ErrorAction Continue "License check failed: $($_.Exception.Message)"
    exit 1
}
