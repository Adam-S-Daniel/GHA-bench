#!/usr/bin/env pwsh
<#
    Invoke-LicenseCheck.ps1

    Entry point used by the CI pipeline. It auto-detects the manifest, policy
    config, and license database inside a project directory, builds the
    compliance report, prints it, and (optionally) fails the build when any
    dependency uses a denied license.

    Conventions inside -ProjectDir:
        package.json OR requirements.txt   -> the dependency manifest
        license-config.json                -> { "allow": [...], "deny": [...] }
        license-db.json                    -> { "name@version": "MIT", ... }

    Exit codes:
        0  success (report produced; no denied deps, or FailOnDenied is off)
        1  a denied license was found AND -FailOnDenied / FAIL_ON_DENIED=true
        2  a configuration / input error (missing files, bad JSON, etc.)
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = '.',
    # When set, exit non-zero if any dependency has a denied license.
    # Defaults from the FAIL_ON_DENIED environment variable so the workflow
    # can toggle it without editing arguments.
    [switch]$FailOnDenied = ($env:FAIL_ON_DENIED -eq 'true')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the checker module that sits next to this script.
Import-Module (Join-Path $PSScriptRoot 'LicenseChecker.psm1') -Force

try {
    $ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path

    # --- Locate the manifest (package.json preferred, then requirements.txt) ---
    $manifest = $null
    foreach ($candidate in 'package.json', 'requirements.txt') {
        $p = Join-Path $ProjectDir $candidate
        if (Test-Path -LiteralPath $p) { $manifest = $p; break }
    }
    if (-not $manifest) {
        throw "No supported manifest (package.json or requirements.txt) found in '$ProjectDir'."
    }

    # --- Locate the policy config ---
    $configPath = Join-Path $ProjectDir 'license-config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Policy config 'license-config.json' not found in '$ProjectDir'."
    }

    # --- Locate the license database (optional but expected in CI) ---
    $dbPath = Join-Path $ProjectDir 'license-db.json'
    if (-not (Test-Path -LiteralPath $dbPath)) {
        throw "License database 'license-db.json' not found in '$ProjectDir'."
    }

    Write-Host "Manifest:  $manifest"
    Write-Host "Config:    $configPath"
    Write-Host "Database:  $dbPath"
    Write-Host ''

    $report = New-ComplianceReport -ManifestPath $manifest -ConfigPath $configPath -DatabasePath $dbPath
    $text   = Format-ComplianceReport -Report $report

    # Print the rendered report so the pipeline can assert on exact values.
    Write-Host $text

    $deniedCount = @($report | Where-Object Status -eq 'denied').Count
    if ($deniedCount -gt 0 -and $FailOnDenied) {
        Write-Error "Compliance check failed: $deniedCount dependency(ies) use a denied license."
        exit 1
    }

    Write-Host 'License compliance check completed successfully.'
    exit 0
}
catch {
    # Graceful, meaningful error reporting.
    Write-Error "License check error: $($_.Exception.Message)"
    exit 2
}
