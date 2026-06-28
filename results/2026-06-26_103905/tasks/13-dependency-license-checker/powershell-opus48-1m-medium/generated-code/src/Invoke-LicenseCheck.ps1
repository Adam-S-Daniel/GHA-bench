#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Dependency License Checker.

.DESCRIPTION
    Parses a manifest, looks up each dependency's license against a local license
    database (a JSON name->license map that stands in for a real registry call,
    keeping CI deterministic and offline), classifies each against the allow/deny
    config, prints a compliance report, and sets the exit code.

.PARAMETER ManifestPath
    Path to package.json or requirements.txt.

.PARAMETER ConfigPath
    Path to the allow/deny license config JSON.

.PARAMETER LicenseDbPath
    Path to the JSON license database (dependency name -> SPDX id).

.PARAMETER FailOnViolation
    If set, exit with code 2 when any dependency is denied. Default: exit 0
    (report-only) so the report can be inspected without failing the build.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ConfigPath,
    [Parameter(Mandatory)][string] $LicenseDbPath,
    [switch] $FailOnViolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Import the module relative to this script so it works from any CWD.
    $modulePath = Join-Path $PSScriptRoot 'LicenseChecker.psm1'
    Import-Module $modulePath -Force

    if (-not (Test-Path -LiteralPath $LicenseDbPath)) {
        throw "License database file not found: '$LicenseDbPath'"
    }

    # Load the license database JSON into a hashtable for Get-DependencyLicense.
    $dbObject = Get-Content -LiteralPath $LicenseDbPath -Raw | ConvertFrom-Json
    $database = @{}
    foreach ($prop in $dbObject.PSObject.Properties) {
        $database[$prop.Name] = $prop.Value
    }

    $report = New-ComplianceReport -ManifestPath $ManifestPath -ConfigPath $ConfigPath -LicenseDatabase $database

    Write-Output (Format-ComplianceReport -Report $report)

    $deniedCount = @($report | Where-Object Status -eq 'denied').Count
    if ($FailOnViolation -and $deniedCount -gt 0) {
        Write-Error "Compliance check failed: $deniedCount denied license(s) found."
        exit 2
    }

    exit 0
}
catch {
    # Graceful, meaningful error reporting.
    Write-Error "Dependency license check failed: $($_.Exception.Message)"
    exit 1
}
