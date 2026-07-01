#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Secret Rotation Validator -- CLI entry point.
.DESCRIPTION
    Loads a secret rotation configuration, computes each secret's rotation
    status (Expired / Warning / Ok) relative to a warning window, and prints
    a rotation report as Markdown or JSON. Intended for use in a scheduled
    CI job that alerts on secrets approaching or past their rotation policy.
.PARAMETER ConfigPath
    Path to the JSON secrets configuration file.
.PARAMETER WarningWindowDays
    Number of days before expiry to flag a secret as "Warning". If omitted,
    falls back to the config file's top-level warningWindowDays, then 14.
.PARAMETER OutputFormat
    'Markdown' (default) or 'Json'.
.PARAMETER AsOf
    Date to evaluate rotation status against. Defaults to the current date.
    Overriding this is primarily useful for deterministic testing/CI fixtures.
.PARAMETER OutputPath
    Optional file path to also write the formatted report to.
.PARAMETER FailOnExpired
    If set, exits with code 1 when any secret is Expired -- useful as a CI
    gate. Without this switch the script always exits 0 on success (report
    generation) regardless of findings, so it can run as a pure reporting step.
.EXAMPLE
    ./SecretRotationValidator.ps1 -ConfigPath ./secrets.json -OutputFormat Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [int]$WarningWindowDays,

    [ValidateSet('Markdown', 'Json')]
    [string]$OutputFormat = 'Markdown',

    [string]$AsOf,

    [string]$OutputPath,

    [switch]$FailOnExpired
)

$ErrorActionPreference = 'Stop'

$ModulePath = Join-Path $PSScriptRoot 'SecretRotationValidator.psm1'
Import-Module $ModulePath -Force

try {
    $config = Import-SecretConfig -Path $ConfigPath
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$effectiveWarningWindow = if ($PSBoundParameters.ContainsKey('WarningWindowDays')) {
    $WarningWindowDays
} elseif ($null -ne $config.WarningWindowDays) {
    $config.WarningWindowDays
} else {
    14
}

$effectiveAsOf = if ($PSBoundParameters.ContainsKey('AsOf')) {
    [datetime]$AsOf
} else {
    Get-Date
}

try {
    $report = New-SecretRotationReport -Secrets $config.Secrets -WarningWindowDays $effectiveWarningWindow -AsOf $effectiveAsOf
    $formatted = Format-SecretRotationReport -Report $report -Format $OutputFormat
} catch {
    Write-Error "Failed to generate rotation report: $($_.Exception.Message)"
    exit 1
}

Write-Output $formatted

if ($OutputPath) {
    Set-Content -LiteralPath $OutputPath -Value $formatted
}

# When running inside GitHub Actions, also surface the report as a job summary.
if ($env:GITHUB_STEP_SUMMARY) {
    $summaryMarkdown = if ($OutputFormat -eq 'Markdown') { $formatted } else { Format-SecretRotationReport -Report $report -Format Markdown }
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summaryMarkdown
}

if ($FailOnExpired -and $report.Summary.ExpiredCount -gt 0) {
    exit 1
}

exit 0
