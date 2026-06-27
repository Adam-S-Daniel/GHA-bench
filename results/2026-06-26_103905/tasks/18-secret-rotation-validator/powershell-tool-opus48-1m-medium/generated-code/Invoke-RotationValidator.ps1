<#
.SYNOPSIS
    CLI entry point for the Secret Rotation Validator.

.DESCRIPTION
    Loads a secrets JSON config, builds the rotation report and prints it in
    the requested format. Exit code reflects urgency so it can gate CI:
        2 = at least one secret expired
        1 = no expired, but at least one in the warning window
        0 = all secrets ok

    -ReferenceDate makes "now" injectable so CI runs are deterministic against
    fixed fixtures.

.EXAMPLE
    pwsh ./Invoke-RotationValidator.ps1 -ConfigPath secrets.json -WarningDays 7 -Format markdown -ReferenceDate 2026-06-26
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [int]$WarningDays = 14,

    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',

    # Defaults to today; overridable for deterministic testing.
    [string]$ReferenceDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module that lives next to this script.
Import-Module (Join-Path $PSScriptRoot 'SecretRotation.psm1') -Force

try {
    $refDate = if ([string]::IsNullOrWhiteSpace($ReferenceDate)) {
        [datetime]::Today
    } else {
        [datetime]::Parse($ReferenceDate)
    }

    $secrets = Import-SecretConfig -Path $ConfigPath
    $report  = New-RotationReport -Secrets $secrets -ReferenceDate $refDate -WarningDays $WarningDays
    $output  = Format-RotationReport -Report $report -Format $Format

    Write-Output $output

    # Exit code communicates the worst urgency found.
    if ($report.summary.expired -gt 0) {
        exit 2
    } elseif ($report.summary.warning -gt 0) {
        exit 1
    } else {
        exit 0
    }
} catch {
    Write-Error "Secret rotation validation failed: $($_.Exception.Message)"
    exit 3
}
