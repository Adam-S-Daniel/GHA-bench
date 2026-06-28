#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Command-line entry point for the Secret Rotation Validator.

.DESCRIPTION
    Thin CLI wrapper around SecretRotationValidator.psm1. It loads a JSON
    configuration of secrets, evaluates each against its rotation policy, and
    prints a rotation report in the requested format. This is the script the
    GitHub Actions workflow invokes (via `shell: pwsh`).

    Reference-date / warning-window precedence (handled by the module):
        explicit parameter  >  value in the config file  >  built-in default

.PARAMETER ConfigPath
    Path to the JSON config. Defaults to the SECRETS_CONFIG_PATH environment
    variable, or 'secrets.json' in the current directory.

.PARAMETER Format
    Output format: Markdown (default), Json, or Summary.

.PARAMETER WarningDays
    Optional override for the warning window. When omitted, the config's
    warningDays (or the 14-day default) is used.

.PARAMETER ReferenceDate
    Optional override for "today" (yyyy-MM-dd). Mainly for deterministic runs.

.PARAMETER FailOnExpired
    When set, exit with code 1 if any secret is Expired (useful as a CI gate).
    By default the script always exits 0 after printing the report.

.EXAMPLE
    ./secret-rotation-validator.ps1 -ConfigPath secrets.json -Format Markdown

.EXAMPLE
    ./secret-rotation-validator.ps1 -Format Summary -WarningDays 30
#>
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [ValidateSet('Markdown', 'Json', 'Summary')] [string] $Format = 'Markdown',
    [int] $WarningDays,
    [string] $ReferenceDate,
    [switch] $FailOnExpired
)

# Stop on the first unhandled error so failures surface clearly in CI logs.
$ErrorActionPreference = 'Stop'

try {
    # Resolve the config path from the parameter, then the environment, then a
    # sensible default. This keeps the workflow YAML simple (it can just rely on
    # the SECRETS_CONFIG_PATH env var).
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = if (-not [string]::IsNullOrWhiteSpace($env:SECRETS_CONFIG_PATH)) {
            $env:SECRETS_CONFIG_PATH
        }
        else {
            'secrets.json'
        }
    }

    # Import the core library that sits next to this script.
    $modulePath = Join-Path $PSScriptRoot 'SecretRotationValidator.psm1'
    Import-Module $modulePath -Force

    # Forward only the overrides that were actually supplied so the module's
    # precedence logic (param > config > default) is preserved.
    $invokeArgs = @{ ConfigPath = $ConfigPath }
    if ($PSBoundParameters.ContainsKey('WarningDays'))   { $invokeArgs['WarningDays']   = $WarningDays }
    if ($PSBoundParameters.ContainsKey('ReferenceDate')) { $invokeArgs['ReferenceDate'] = $ReferenceDate }

    # Render the report in the requested format and emit it to stdout.
    $output = Invoke-SecretRotationValidator @invokeArgs -Format $Format
    Write-Output $output

    # Optional CI gate: parse the stable Summary contract to detect expired secrets.
    if ($FailOnExpired) {
        $summaryLine = (Invoke-SecretRotationValidator @invokeArgs -Format Summary -ErrorAction Stop) `
            -split "`r?`n" | Select-Object -First 1
        $expiredCount = 0
        if ($summaryLine -match 'expired=(\d+)') { $expiredCount = [int]$Matches[1] }
        if ($expiredCount -gt 0) {
            Write-Error "Found $expiredCount expired secret(s); rotation required."
            exit 1
        }
    }

    exit 0
}
catch {
    # Surface a clean, single-line error message (no PowerShell stack noise) so
    # the failure is obvious in the GitHub Actions log.
    Write-Error "secret-rotation-validator failed: $($_.Exception.Message)"
    exit 2
}
