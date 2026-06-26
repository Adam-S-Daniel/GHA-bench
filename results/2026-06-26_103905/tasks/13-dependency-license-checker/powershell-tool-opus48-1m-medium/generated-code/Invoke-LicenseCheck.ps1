#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Dependency License Checker.
.DESCRIPTION
    Generates a compliance report for a manifest and prints it in a stable,
    machine-parseable format (one RESULT line per dependency plus SUMMARY and
    COMPLIANCE lines). Designed to be invoked from CI.

    Exit codes:
      0 = compliant (no denied licenses)
      1 = non-compliant (one or more denied licenses)
      2 = error (bad input, parse failure, etc.)
.EXAMPLE
    ./Invoke-LicenseCheck.ps1 -ManifestPath fixtures/package.json `
        -ConfigPath config/license-config.json -DatabasePath config/license-db.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$DatabasePath,
    # When set, non-compliance (denied licenses) causes a non-zero exit code.
    [switch]$FailOnViolation
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src' 'DependencyLicenseChecker.psm1') -Force

try {
    $report = New-ComplianceReport -ManifestPath $ManifestPath -ConfigPath $ConfigPath -DatabasePath $DatabasePath
}
catch {
    Write-Error "License check failed: $($_.Exception.Message)"
    exit 2
}

Write-Output "=== Dependency License Compliance Report ==="
Write-Output "Manifest: $($report.Manifest)"
Write-Output ""

# One stable, greppable line per dependency.
foreach ($r in $report.Results) {
    Write-Output ("RESULT name={0} version={1} scope={2} license={3} status={4}" -f `
        $r.Name, $r.Version, $r.Scope, $r.License, $r.Status)
}

Write-Output ""
Write-Output ("SUMMARY approved={0} denied={1} unknown={2} total={3}" -f `
    $report.Summary.Approved, $report.Summary.Denied, $report.Summary.Unknown, $report.Summary.Total)

$complianceText = if ($report.Compliant) { 'PASS' } else { 'FAIL' }
Write-Output "COMPLIANCE $complianceText"

if (-not $report.Compliant -and $FailOnViolation) {
    exit 1
}

exit 0
