#!/usr/bin/env pwsh
<#
    .SYNOPSIS
    Dependency license compliance checker CLI.

    .DESCRIPTION
    Parses a dependency manifest (package.json or requirements.txt),
    resolves each dependency's license, and compares it against an
    allow-list/deny-list policy. Prints a compliance report and exits
    non-zero if any dependency is Denied.

    -MockDataPath is used to seed the license lookup for testing/CI, so
    the checker never needs to make a real network call to a package
    registry.

    .EXAMPLE
    ./Check-Licenses.ps1 -ManifestPath package.json -PolicyPath license-policy.json -MockDataPath mock-licenses.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$PolicyPath,

    [Parameter()]
    [string]$MockDataPath
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src' 'LicenseChecker.psm1'
Import-Module $modulePath -Force

try {
    Clear-MockPackageLicense

    if ($MockDataPath) {
        if (-not (Test-Path -LiteralPath $MockDataPath)) {
            throw "Mock license data file not found: $MockDataPath"
        }
        $mockData = Get-Content -LiteralPath $MockDataPath -Raw | ConvertFrom-Json
        foreach ($prop in $mockData.PSObject.Properties) {
            $parts = $prop.Name -split '@', 2
            Set-MockPackageLicense -Name $parts[0] -Version $parts[1] -License $prop.Value
        }
    }

    $policy = Get-LicensePolicy -Path $PolicyPath
    $dependencies = Get-DependenciesFromManifest -Path $ManifestPath
    $report = New-ComplianceReport -Dependencies $dependencies -Policy $policy

    Write-Output '=== Dependency License Compliance Report ==='
    foreach ($entry in $report) {
        Write-Output ("{0,-20} {1,-15} {2,-12} {3}" -f $entry.Name, $entry.Version, $entry.License, $entry.Status)
    }

    $denied = @($report | Where-Object Status -eq 'Denied')
    $unknown = @($report | Where-Object Status -eq 'Unknown')
    $approved = @($report | Where-Object Status -eq 'Approved')

    Write-Output ''
    Write-Output "Summary: $($approved.Count) Approved, $($denied.Count) Denied, $($unknown.Count) Unknown"

    if ($denied.Count -gt 0) {
        Write-Output "COMPLIANCE FAILED: $($denied.Count) dependencies use a denied license."
        exit 1
    }

    Write-Output 'COMPLIANCE PASSED.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 2
}
