#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Dependency license compliance checker (CLI entry point).

.DESCRIPTION
    Parses a dependency manifest (package.json or requirements.txt), resolves
    each dependency's license via a local (mockable) license database, classifies
    it against an allow/deny license config, and prints a deterministic
    compliance report.

    By default the script runs in "report mode" and exits 0 regardless of the
    compliance verdict (the verdict is in the report text). Pass -FailOnViolation
    to make the process exit non-zero (1) when any denied license is found, which
    is the mode you would use to gate a real CI pipeline.

    Exit codes:
        0  success (report mode, or compliant under -FailOnViolation)
        1  a denied license was found AND -FailOnViolation was set
        2  a usage / IO error occurred (missing files, bad JSON, etc.)

.PARAMETER ManifestPath
    Path to the manifest file, OR a directory containing a package.json /
    requirements.txt (the first one found is used).

.PARAMETER ConfigPath
    Path to the license allow/deny config JSON: { "allow": [...], "deny": [...] }.

.PARAMETER LicenseDbPath
    Path to the (mock) license database JSON: { "<package>": "<license-id>" }.

.PARAMETER FailOnViolation
    Exit 1 when any dependency has a denied license.

.EXAMPLE
    ./Invoke-LicenseCheck.ps1 -ManifestPath ./package.json `
        -ConfigPath ./config/license-config.json -LicenseDbPath ./fixtures/license-db.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LicenseDbPath,

    [switch]$FailOnViolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the function library that holds all the testable logic.
Import-Module (Join-Path $PSScriptRoot 'src/LicenseChecker.psm1') -Force

try {
    # If a directory is supplied, auto-discover a supported manifest inside it.
    if (Test-Path -LiteralPath $ManifestPath -PathType Container) {
        $candidate = Get-ChildItem -LiteralPath $ManifestPath -File |
            Where-Object { $_.Name -in 'package.json', 'requirements.txt' } |
            Select-Object -First 1
        if (-not $candidate) {
            throw "No supported manifest (package.json / requirements.txt) found in directory '$ManifestPath'"
        }
        $ManifestPath = $candidate.FullName
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "License config not found: '$ConfigPath'"
    }

    # Load and validate the allow/deny config.
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse license config '$ConfigPath': $($_.Exception.Message)"
    }
    foreach ($field in 'allow', 'deny') {
        if ($config.PSObject.Properties.Name -notcontains $field) {
            throw "License config '$ConfigPath' is missing required '$field' array"
        }
    }

    # Parse -> resolve licenses -> classify -> render.
    $dependencies = @(ConvertFrom-DependencyManifest -Path $ManifestPath)
    $report       = New-ComplianceReport -Dependencies $dependencies -Config $config -DatabasePath $LicenseDbPath
    $text         = Format-ComplianceReport -Report $report

    Write-Output $text

    if ($FailOnViolation -and ($report | Where-Object Status -eq 'denied')) {
        exit 1
    }
    # Report mode: return normally (exit code 0). We intentionally do NOT call
    # `exit 0` here so the script can be dot-invoked inside a larger pwsh step
    # (e.g. a CI run block) without terminating the surrounding session.
}
catch {
    # Graceful, meaningful error reporting. Write straight to stderr rather than
    # Write-Error, because $ErrorActionPreference='Stop' would otherwise re-throw
    # this and bypass our controlled exit code.
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 2
}
