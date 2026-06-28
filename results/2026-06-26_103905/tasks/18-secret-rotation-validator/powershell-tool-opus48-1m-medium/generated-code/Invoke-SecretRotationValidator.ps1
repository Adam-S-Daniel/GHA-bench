#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Secret Rotation Validator.

.DESCRIPTION
    Loads a secrets config JSON file, evaluates each secret's rotation status
    against a reference date and warning window, then writes the report to
    stdout in the requested format (markdown or json).

    Designed to run unattended in CI: the reference date is an explicit
    parameter (defaulting to today) so output is reproducible in tests.

.PARAMETER ConfigPath
    Path to the secrets config JSON file.

.PARAMETER ReferenceDate
    The "today" date for the evaluation (ISO yyyy-MM-dd). Defaults to today.

.PARAMETER WarningWindowDays
    Days ahead of the due date that count as a warning. Default 14.

.PARAMETER Format
    Output format: markdown (default) or json.

.EXAMPLE
    ./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -ReferenceDate 2026-06-01 -Format json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [string] $ReferenceDate = (Get-Date -Format 'yyyy-MM-dd'),
    [int]    $WarningWindowDays = 14,
    [ValidateSet('markdown', 'json')] [string] $Format = 'markdown'
)

# Stop on any error so failures surface as a non-zero exit code in CI.
$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'src/SecretRotationValidator.psm1'
    Import-Module $modulePath -Force

    $secrets = Import-SecretConfig -Path $ConfigPath
    $report  = New-RotationReport -Secrets $secrets -ReferenceDate $ReferenceDate -WarningWindowDays $WarningWindowDays
    $output  = Format-RotationReport -Report $report -Format $Format

    Write-Output $output

    # Emit a concise, easy-to-assert status line to stderr-free stdout for CI.
    Write-Output ''
    Write-Output ("ROTATION_SUMMARY expired={0} warning={1} ok={2} total={3}" -f `
        $report.summary.expired, $report.summary.warning, $report.summary.ok, $report.summary.total)
}
catch {
    Write-Error "Secret rotation validation failed: $($_.Exception.Message)"
    exit 1
}
