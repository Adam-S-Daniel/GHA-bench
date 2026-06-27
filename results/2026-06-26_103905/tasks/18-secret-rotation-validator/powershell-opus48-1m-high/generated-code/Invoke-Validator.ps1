#!/usr/bin/env pwsh
#
# Invoke-Validator.ps1
#
# CLI entrypoint for the Secret Rotation Validator. Loads a secrets config,
# evaluates rotation urgency, prints a report in the requested format, and
# (optionally) fails the process when expired secrets are found so it can act
# as a CI gate.
#
# Exit codes:
#   0  success (no gate failure)
#   1  operational error (bad config path, invalid JSON, malformed secret)
#   2  gate failure: expired secrets present AND -FailOnExpired was supplied
#
# All real work lives in SecretRotationValidator.psm1; this script is a thin,
# testable shell around it that handles argument parsing and exit codes.
#
[CmdletBinding()]
param(
    # Path to the JSON config. Falls back to the SECRETS_CONFIG env var, then
    # to the bundled default fixture so the workflow has a sensible default.
    [string] $ConfigPath = $(if ($env:SECRETS_CONFIG) { $env:SECRETS_CONFIG } else { Join-Path $PSScriptRoot 'fixtures/secrets.json' }),

    # Warning window in days. Falls back to WARNING_DAYS env var, else 14.
    [int] $WarningDays = $(if ($env:WARNING_DAYS) { [int]$env:WARNING_DAYS } else { 14 }),

    # Output format. Falls back to OUTPUT_FORMAT env var, else markdown.
    [ValidateSet('markdown', 'json')]
    [string] $Format = $(if ($env:OUTPUT_FORMAT) { $env:OUTPUT_FORMAT } else { 'markdown' }),

    # The date treated as "now". Falls back to REFERENCE_DATE env var, else
    # today. Pinning this keeps CI output deterministic across fixtures.
    [string] $ReferenceDate = $(if ($env:REFERENCE_DATE) { $env:REFERENCE_DATE } else { (Get-Date).ToString('yyyy-MM-dd') }),

    # When set, exit 2 if any secret is expired (turns the report into a gate).
    [switch] $FailOnExpired
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the core module relative to this script.
Import-Module (Join-Path $PSScriptRoot 'SecretRotationValidator.psm1') -Force

try {
    $secrets = Import-SecretConfig -Path $ConfigPath
    $report = Get-SecretRotationReport -Secrets $secrets -ReferenceDate $ReferenceDate -WarningDays $WarningDays
    $rendered = Format-RotationReport -Report $report -Format $Format
    Write-Output $rendered
}
catch {
    # Operational failure: surface a clear, actionable message on stderr.
    # Write directly to stderr (not Write-Error) so the chosen exit code wins
    # instead of the Stop preference promoting it to a generic exit 1.
    [Console]::Error.WriteLine("Secret rotation validation failed: $($_.Exception.Message)")
    exit 1
}

# Optional CI gate: non-zero exit when expired secrets exist.
if ($FailOnExpired -and $report.summary.expired -gt 0) {
    [Console]::Error.WriteLine("Gate failure: $($report.summary.expired) secret(s) are expired and require immediate rotation.")
    exit 2
}

exit 0
