#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Entry point for the dependency license compliance checker.

.DESCRIPTION
    Wires the LicenseChecker module together end-to-end:

      1. Loads the allow/deny license config (JSON).
      2. Loads the mock license database (JSON map of package -> license).
         In production this file would be replaced by a real registry lookup;
         it is the offline, deterministic stand-in used by tests and CI.
      3. Parses the dependency manifest (package.json / requirements.txt).
      4. Builds a compliance report and writes it as JSON.
      5. Prints a human-readable report to stdout.

    Errors are caught and reported with meaningful messages; the script exits 1
    on operational failure. License non-compliance only forces a non-zero exit
    when -FailOnDenied is supplied, so the same script can be used both as a
    pure reporter and as a CI gate.

.PARAMETER ManifestPath
    Path to the dependency manifest to scan.

.PARAMETER ConfigPath
    Path to the JSON license config containing `allow` and `deny` arrays.

.PARAMETER LicenseDbPath
    Path to the JSON mock license database (object: { "pkg": "LICENSE", ... }).

.PARAMETER OutputJsonPath
    Where to write the machine-readable JSON report. Defaults to
    ./compliance-report.json.

.PARAMETER FailOnDenied
    If set, the script exits 1 when any dependency has a denied license.

.EXAMPLE
    ./Invoke-LicenseChecker.ps1 -ManifestPath package.json `
        -ConfigPath config/license-config.json `
        -LicenseDbPath config/license-db.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LicenseDbPath,

    [Parameter()]
    [string]$OutputJsonPath = (Join-Path (Get-Location) 'compliance-report.json'),

    [Parameter()]
    [switch]$FailOnDenied
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Resolve the module relative to this script so it works from any CWD.
    $modulePath = Join-Path $PSScriptRoot 'src/LicenseChecker.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "LicenseChecker module not found at '$modulePath'"
    }
    Import-Module $modulePath -Force

    # --- Load config (allow / deny lists) ---------------------------------
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "License config not found: '$ConfigPath'"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    # --- Load the mock license database -----------------------------------
    if (-not (Test-Path -LiteralPath $LicenseDbPath)) {
        throw "License database not found: '$LicenseDbPath'"
    }
    $dbObject = Get-Content -LiteralPath $LicenseDbPath -Raw | ConvertFrom-Json
    $licenseDb = @{}
    foreach ($prop in $dbObject.PSObject.Properties) {
        $licenseDb[$prop.Name] = $prop.Value
    }

    # --- Parse manifest & build the report --------------------------------
    $deps   = @(Get-Dependencies -ManifestPath $ManifestPath)
    $report = New-ComplianceReport -Dependencies $deps -Config $config -LicenseDatabase $licenseDb

    # --- Persist machine-readable JSON ------------------------------------
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputJsonPath -Encoding utf8
    Write-Verbose "Wrote JSON report to '$OutputJsonPath'"

    # --- Print human-readable report --------------------------------------
    Write-Output (Format-ComplianceReport -Report $report)

    # --- Optional CI gate -------------------------------------------------
    if ($FailOnDenied -and -not $report.Compliant) {
        Write-Error "Compliance check failed: $($report.Summary.Denied) denied license(s) found."
        exit 1
    }

    exit 0
}
catch {
    Write-Error "license-checker error: $($_.Exception.Message)"
    exit 1
}
