#!/usr/bin/env pwsh
# Validate-SecretRotation.ps1
#
# Thin CLI wrapper around the SecretRotation.ps1 library. This is the entry
# point referenced by the GitHub Actions workflow.
#
# Usage:
#   pwsh ./Validate-SecretRotation.ps1 -ConfigPath secrets.json `
#        -WarningWindowDays 7 -Format markdown [-AsOf 2026-06-26] [-FailOnExpired]
#
# Behaviour:
#   * Prints the formatted rotation report to stdout.
#   * Exits 0 on success.
#   * Exits 2 on any validation/IO error (with a meaningful message on stderr).
#   * Exits 1 when -FailOnExpired is set AND expired secrets were found
#     (useful for gating a CI pipeline without breaking the default run).

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath,
    [int]    $WarningWindowDays = 7,
    [ValidateSet('markdown', 'json')] [string] $Format = 'markdown',
    # Defaults to "today" but can be pinned for deterministic output/tests.
    [string] $AsOf = '',
    [switch] $FailOnExpired
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the pure-function library next to this script.
. (Join-Path $PSScriptRoot 'SecretRotation.ps1')

try {
    $asOfDate =
        if ([string]::IsNullOrWhiteSpace($AsOf)) { (Get-Date).Date }
        else {
            [datetime]$tmp = [datetime]::MinValue
            if (-not [datetime]::TryParse($AsOf, [ref]$tmp)) {
                throw "Invalid -AsOf date: '$AsOf' (expected yyyy-MM-dd)"
            }
            $tmp.Date
        }

    $secrets = Read-SecretConfig -Path $ConfigPath
    $report  = New-RotationReport -Secrets $secrets -AsOf $asOfDate -WarningWindowDays $WarningWindowDays

    $rendered =
        switch ($Format) {
            'markdown' { Format-RotationReportMarkdown -Report $report }
            'json'     { Format-RotationReportJson -Report $report }
        }

    Write-Output $rendered

    if ($FailOnExpired -and $report.summary.expired -gt 0) {
        Write-Error "Found $($report.summary.expired) expired secret(s)."
        exit 1
    }

    exit 0
}
catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 2
}
