#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point: apply artifact retention policies to a JSON fixture and
    print a deletion plan + machine-readable metrics.

.DESCRIPTION
    Thin wrapper around the ArtifactCleanup module. Designed to run unchanged
    locally, in CI, and inside an `act` container. Policy thresholds and the
    reference date default to whatever the fixture provides, but can be
    overridden with parameters / environment variables.

    Output is split into two parts so a CI harness can assert on exact values:
      * a human-readable report
      * a delimited "METRICS" block of KEY=VALUE lines

.PARAMETER FixturePath
    Path to the artifact metadata JSON (mock data).

.PARAMETER DryRun
    When set, no deletions are performed (the deletion side effect is skipped).

.EXAMPLE
    pwsh ./Invoke-ArtifactCleanup.ps1 -FixturePath fixtures/standard.json -DryRun
#>
[CmdletBinding()]
param(
    [string]$FixturePath = $env:ARTIFACT_FIXTURE,
    [string]$CaseName,
    [switch]$DryRun,

    # Optional overrides; 0/unset means "use the fixture's value".
    [int]$MaxAgeDays = 0,
    [int]$KeepLatestPerWorkflow = 0,
    [long]$MaxTotalSizeBytes = 0,

    # Reference "now". Defaults to the fixture's referenceDate, then to today.
    [string]$Now
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Import the cleanup library relative to this script (CWD-independent).
$modulePath = Join-Path $PSScriptRoot 'ArtifactCleanup.psm1'
Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    throw "No fixture supplied. Pass -FixturePath or set the ARTIFACT_FIXTURE environment variable."
}

# Build the argument splat, forwarding only the overrides the caller actually set
# so the module can fall back to the fixture's own policy/date defaults.
$invokeArgs = @{ Path = $FixturePath }
if ($DryRun)                                  { $invokeArgs.DryRun = $true }
if ($PSBoundParameters.ContainsKey('MaxAgeDays'))            { $invokeArgs.MaxAgeDays = $MaxAgeDays }
if ($PSBoundParameters.ContainsKey('KeepLatestPerWorkflow')) { $invokeArgs.KeepLatestPerWorkflow = $KeepLatestPerWorkflow }
if ($PSBoundParameters.ContainsKey('MaxTotalSizeBytes'))     { $invokeArgs.MaxTotalSizeBytes = $MaxTotalSizeBytes }
if ($PSBoundParameters.ContainsKey('Now') -and $Now)         { $invokeArgs.Now = [datetime]$Now }

$label = if ($CaseName) { $CaseName } else { Split-Path -Leaf $FixturePath }

Write-Output "=== CASE: $label ==="
$result = Invoke-ArtifactCleanup @invokeArgs

# Human-readable plan.
$result.ReportLines | ForEach-Object { Write-Output $_ }

# Machine-readable, exact-value metrics for the CI harness to assert on.
Write-Output '--- METRICS ---'
$result.MetricLines | ForEach-Object { Write-Output $_ }
Write-Output "=== END CASE: $label ==="
Write-Output ''
