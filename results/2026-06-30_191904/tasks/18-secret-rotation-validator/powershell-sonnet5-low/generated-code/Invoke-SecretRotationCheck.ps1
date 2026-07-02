<#
    .SYNOPSIS
    CLI entrypoint: validates secret rotation status against a config file
    and prints a rotation report.

    .DESCRIPTION
    Loads secret metadata from -ConfigPath, evaluates each secret's rotation
    status relative to -WarningDays and -AsOf, prints a report in the
    requested -Format, and sets the process exit code to 1 if any secret is
    Expired or in the Warning window (0 otherwise) so CI can fail the build.

    .PARAMETER ConfigPath
    Path to a JSON file describing secrets (Name, LastRotated,
    RotationPolicyDays, RequiredBy).

    .PARAMETER WarningDays
    Number of days before expiry to start flagging a secret as Warning.

    .PARAMETER AsOf
    The reference date to evaluate rotation status against. Defaults to now.

    .PARAMETER Format
    Output format: Markdown or Json.
#>
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [int]$WarningDays = 14,

    [datetime]$AsOf = (Get-Date),

    [ValidateSet('Markdown', 'Json')]
    [string]$Format = 'Markdown'
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SecretRotationValidator.psm1') -Force

$secrets = Import-SecretConfig -Path $ConfigPath
$report = Get-RotationReport -Secrets $secrets -WarningDays $WarningDays -AsOf $AsOf
$rendered = Format-RotationReport -Report $report -Format $Format

Write-Output $rendered

if ($report.Summary.ExpiredCount -gt 0 -or $report.Summary.WarningCount -gt 0) {
    exit 1
}
else {
    exit 0
}
