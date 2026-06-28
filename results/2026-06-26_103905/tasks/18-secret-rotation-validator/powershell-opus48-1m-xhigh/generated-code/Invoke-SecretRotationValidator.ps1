#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the Secret Rotation Validator.

.DESCRIPTION
    Loads a secrets configuration file, classifies each secret by rotation
    urgency (expired / warning / ok) relative to a reference date and a
    configurable warning window, renders a rotation report in the requested
    format (markdown or json), and emits a machine-parseable RESULT summary line.

    The RESULT line has a stable, grep-friendly shape so CI jobs (and the act
    test harness) can assert on exact counts regardless of log decoration:

        RESULT fixture=<label> expired=<n> warning=<n> ok=<n> total=<n>

    Exit codes:
        0  success (report produced; no failing condition triggered)
        1  -FailOnExpired was set and at least one secret is expired
        2  a usage / input error occurred (bad path, malformed config, etc.)

.PARAMETER ConfigPath
    Path to the secrets configuration JSON file.

.PARAMETER Format
    Output format: 'markdown' (default) or 'json'.

.PARAMETER WarningWindowDays
    Override the warning window (days). Falls back to the config value, then 30.

.PARAMETER AsOf
    Override the reference date (yyyy-MM-dd). Falls back to the config value,
    then today. Provided primarily for deterministic testing.

.PARAMETER Label
    Identifier recorded on the report and the RESULT line. Defaults to the
    config file's base name (e.g. 'mixed' for fixtures/mixed.json).

.PARAMETER FailOnExpired
    If set, exit with code 1 when any secret is expired (useful for gating CI).

.EXAMPLE
    ./Invoke-SecretRotationValidator.ps1 -ConfigPath fixtures/mixed.json -Format markdown
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [string] $Format = 'markdown',
    [int] $WarningWindowDays,
    [string] $AsOf,
    [string] $Label,
    [switch] $FailOnExpired
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the core library from alongside this script (robust regardless of CWD).
$modulePath = Join-Path $PSScriptRoot 'SecretRotation.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "Cannot find SecretRotation.psm1 next to this script (looked in '$PSScriptRoot')."
    exit 2
}
Import-Module $modulePath -Force

try {
    # Default the label to the config file's base name for self-identification.
    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    }

    $config = Import-SecretConfig -Path $ConfigPath

    # Only forward overrides that were actually supplied so config/defaults win
    # otherwise. Splatting keeps the precedence logic inside Get-RotationReport.
    $reportArgs = @{ Config = $config; Label = $Label }
    if ($PSBoundParameters.ContainsKey('WarningWindowDays')) { $reportArgs.WarningWindowDays = $WarningWindowDays }
    if ($PSBoundParameters.ContainsKey('AsOf') -and -not [string]::IsNullOrWhiteSpace($AsOf)) { $reportArgs.AsOf = $AsOf }

    $report = Get-RotationReport @reportArgs
    $rendered = Format-RotationReport -Report $report -Format $Format

    # The rendered report (human/machine readable, depending on -Format).
    Write-Output $rendered

    # Always emit the stable summary line on its own, after the report body.
    $s = $report.summary
    Write-Output ("RESULT fixture={0} expired={1} warning={2} ok={3} total={4}" -f `
        $report.label, $s.expired, $s.warning, $s.ok, $s.total)

    if ($FailOnExpired -and $s.expired -gt 0) {
        # Write to stderr directly: with $ErrorActionPreference='Stop', Write-Error
        # would itself terminate before `exit` could set the intended code.
        [Console]::Error.WriteLine("secret-rotation-validator: $($s.expired) expired secret(s) found.")
        exit 1
    }

    # Success: return naturally (process exit code 0). Avoiding an explicit
    # `exit 0` lets a caller `&`-invoke this script and keep executing afterwards
    # (e.g. to also write the report to a CI job summary).
}
catch {
    # Surface a clean, meaningful message rather than a raw stack trace, then
    # exit 2 to signal a usage/input error distinct from the gating exit 1.
    [Console]::Error.WriteLine("secret-rotation-validator: $($_.Exception.Message)")
    exit 2
}
