<#
.SYNOPSIS
    CI entry point for the Secret Rotation Validator.
.DESCRIPTION
    Loads the secret configuration, builds a rotation report, prints it in
    the requested format, and optionally writes it to -OutputPath. The
    report is always printed/written even when -FailOnExpired triggers a
    non-zero exit, so the CI logs/artifacts still show what was found.
.EXAMPLE
    ./Invoke-RotationCheck.ps1 -ConfigPath ../secrets-config.json -OutputFormat Markdown
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'secrets-config.json'),
    [int]$WarningDays = 14,
    [ValidateSet('Markdown', 'Json')]
    [string]$OutputFormat = 'Markdown',
    [string]$OutputPath,
    [switch]$FailOnExpired
)

$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path $PSScriptRoot '..'
Import-Module (Join-Path $moduleRoot 'SecretRotationValidator.psm1') -Force

try {
    $secrets = Import-SecretConfig -Path $ConfigPath
    $report = New-RotationReport -Secrets $secrets -WarningDays $WarningDays -Now (Get-Date)
    $formatted = Format-RotationReport -Report $report -Format $OutputFormat
}
catch {
    Write-Error "Secret rotation check could not run: $($_.Exception.Message)"
    exit 1
}

Write-Output $formatted

if ($OutputPath) {
    Set-Content -Path $OutputPath -Value $formatted
}

if ($FailOnExpired -and $report.Summary.ExpiredCount -gt 0) {
    Write-Error "Secret rotation check failed: $($report.Summary.ExpiredCount) secret(s) have expired rotation policies."
    exit 1
}
