<#
.SYNOPSIS
    CLI entry point for the secret rotation validator (used by CI).

.DESCRIPTION
    Loads a secrets config, evaluates rotation status against an as-of date,
    and prints the report to stdout in the requested format.

    Exit codes (designed for CI):
      0 - report generated (and no expired secrets, or -FailOnExpired not set)
      1 - operational error (bad config, bad arguments) with message on stderr
      2 - -FailOnExpired was set and at least one secret is expired

.PARAMETER ConfigPath
    Path to the secrets JSON config file.

.PARAMETER WarningWindowDays
    Warning window override in days. -1 (default) uses the config file value.

.PARAMETER Format
    Output format: Markdown (default) or Json.

.PARAMETER AsOfDate
    Evaluation date as yyyy-MM-dd. Defaults to today. Injectable so CI test
    runs are deterministic.

.PARAMETER FailOnExpired
    Exit with code 2 when any secret is expired (lets a pipeline gate on it).

.EXAMPLE
    ./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -Format Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [ValidateRange(-1, 3650)] [int] $WarningWindowDays = -1,
    [ValidateSet('Markdown', 'Json')] [string] $Format = 'Markdown',
    [string] $AsOfDate = '',
    [switch] $FailOnExpired
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'src' 'SecretRotationValidator.psm1') -Force

    # Resolve the as-of date: strict ISO parse when given, today otherwise.
    $asOf = if ([string]::IsNullOrWhiteSpace($AsOfDate)) {
        (Get-Date).Date
    }
    else {
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($AsOfDate, 'yyyy-MM-dd',
                [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$parsed)) {
            throw "Invalid -AsOfDate '$AsOfDate' (expected yyyy-MM-dd)."
        }
        $parsed
    }

    $report = Get-RotationReport -ConfigPath $ConfigPath -AsOfDate $asOf -WarningWindowDays $WarningWindowDays
    Format-RotationReport -Report $report -Format $Format | Write-Output

    if ($FailOnExpired -and $report.Summary.Expired -gt 0) {
        Write-Error -ErrorAction Continue "FailOnExpired: $($report.Summary.Expired) secret(s) are expired."
        exit 2
    }
    exit 0
}
catch {
    Write-Error -ErrorAction Continue "secret-rotation-validator: $($_.Exception.Message)"
    exit 1
}
