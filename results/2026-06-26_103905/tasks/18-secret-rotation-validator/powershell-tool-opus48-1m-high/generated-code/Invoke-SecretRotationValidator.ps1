#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Secret Rotation Validator.

.DESCRIPTION
    Loads a secrets configuration file, evaluates every secret against a reference
    date and a configurable warning window, and prints a rotation report grouped by
    urgency (expired / warning / ok) in either markdown or JSON.

    This thin wrapper is what the GitHub Actions workflow invokes; all logic lives
    in the SecretRotationValidator.psm1 module so it can be unit-tested in isolation.

.PARAMETER ConfigPath
    Path to the secrets configuration JSON file. Defaults to fixtures/secrets.json.

.PARAMETER WarningDays
    Override the warning window (in days). When omitted, the value from the config
    file is used, falling back to 14.

.PARAMETER Format
    Output format: 'markdown' (default) or 'json'.

.PARAMETER ReferenceDate
    Override the reference ("today") date in yyyy-MM-dd form. When omitted, the
    value from the config file is used, falling back to the real current date.

.PARAMETER FailOnExpired
    When set, the script exits with code 2 if any secret is expired. Useful for
    failing a CI job when rotation is overdue.

.EXAMPLE
    ./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/secrets.json -Format json
#>
[CmdletBinding()]
param(
    [string] $ConfigPath = 'fixtures/secrets.json',

    [int] $WarningDays = -1,   # sentinel: -1 means "not supplied, use config/default"

    [ValidateSet('markdown', 'json')]
    [string] $Format = 'markdown',

    [string] $ReferenceDate,

    [switch] $FailOnExpired
)

# Stop on the first unhandled error and surface a clean message instead of a stack trace.
$ErrorActionPreference = 'Stop'

try {
    # Import the module living next to this script (works regardless of CWD).
    $modulePath = Join-Path $PSScriptRoot 'SecretRotationValidator.psm1'
    Import-Module $modulePath -Force

    $config = Import-SecretConfig -Path $ConfigPath

    # Build a splat so unset overrides cleanly defer to the module's resolution logic.
    $reportArgs = @{ Config = $config }
    if ($WarningDays -ge 0) { $reportArgs['WarningDays'] = $WarningDays }
    if (-not [string]::IsNullOrWhiteSpace($ReferenceDate)) { $reportArgs['ReferenceDate'] = $ReferenceDate }

    $report = New-RotationReport @reportArgs

    Format-RotationReport -Report $report -Format $Format | Write-Output

    if ($FailOnExpired -and $report.Counts.Expired -gt 0) {
        # Emit to stderr so it does not pollute the parseable report on stdout.
        [Console]::Error.WriteLine("ERROR: $($report.Counts.Expired) secret(s) are expired and require immediate rotation.")
        exit 2
    }

    exit 0
}
catch {
    # Graceful, meaningful failure: clean message, no PowerShell stack noise.
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
