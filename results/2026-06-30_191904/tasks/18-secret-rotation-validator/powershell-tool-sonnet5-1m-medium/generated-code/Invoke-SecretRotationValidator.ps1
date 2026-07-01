#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Secret Rotation Validator.
.DESCRIPTION
    Loads a secrets configuration file, evaluates each secret's rotation
    status, and prints/writes a rotation report grouped by urgency
    (Expired / Warning / Ok). Exits non-zero when any secret is expired so
    the tool can be wired into a CI gate.
.PARAMETER ConfigPath
    Path to the JSON secrets configuration file.
.PARAMETER WarningDays
    Overrides the warning window (in days) from the config file.
.PARAMETER Format
    Output format: Markdown (default) or Json.
.PARAMETER OutputPath
    Optional path to write the rendered report to, in addition to stdout.
.PARAMETER Now
    Overrides "today" for deterministic runs (e.g. in CI or tests).
    Defaults to the current date.
.PARAMETER FailOnExpired
    When set (default), the script exits with code 1 if any secret is
    expired. Pass -FailOnExpired:$false to always exit 0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [int]$WarningDays,

    [ValidateSet('Markdown', 'Json')]
    [string]$Format = 'Markdown',

    [string]$OutputPath,

    [string]$Now,

    [bool]$FailOnExpired = $true
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SecretRotationValidator.psm1') -Force

try {
    $config = Import-SecretConfig -Path $ConfigPath

    $effectiveWarningDays = if ($PSBoundParameters.ContainsKey('WarningDays')) { $WarningDays } else { $config.WarningDays }
    $effectiveNow = if ($Now) { [datetime]$Now } else { Get-Date }

    $report = New-SecretRotationReport -Secrets $config.Secrets -WarningDays $effectiveWarningDays -Now $effectiveNow
    $rendered = Format-SecretRotationReport -Report $report -Format $Format

    Write-Output $rendered

    if ($OutputPath) {
        Set-Content -Path $OutputPath -Value $rendered
    }

    if ($FailOnExpired -and $report.Summary.ExpiredCount -gt 0) {
        Write-Error "$($report.Summary.ExpiredCount) secret(s) are expired and require rotation." -ErrorAction Continue
        exit 1
    }

    exit 0
} catch {
    Write-Error "Secret Rotation Validator failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 2
}
