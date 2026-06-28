#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Command-line entry point for the artifact cleanup engine. Designed to be
    called from CI (GitHub Actions / act).

.DESCRIPTION
    Loads artifact metadata from a JSON fixture, applies the requested retention
    policies and prints both a human-readable summary and a set of machine-
    parseable "RESULT:" lines that the test harness asserts on.

    A fixed -ReferenceTime (or the ARTIFACT_REF_TIME env var) makes the age-based
    policies deterministic so CI output is reproducible.

.EXAMPLE
    ./Invoke-Cleanup.ps1 -Path fixtures/sample.json -MaxAgeDays 30 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [int]  $MaxAgeDays            = 0,
    [int]  $KeepLatestPerWorkflow = 0,
    [long] $MaxTotalSizeBytes     = 0,

    [switch] $DryRun,

    # Reference "now". Falls back to ARTIFACT_REF_TIME env var, then real now.
    [string] $ReferenceTime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'src' 'ArtifactCleanup.psm1') -Force

    # Resolve the reference time (param > env var > now).
    $refTime = if ($ReferenceTime) {
        [datetime] $ReferenceTime
    }
    elseif ($env:ARTIFACT_REF_TIME) {
        [datetime] $env:ARTIFACT_REF_TIME
    }
    else {
        Get-Date
    }

    # Only forward policies that were explicitly enabled (non-zero).
    $invokeArgs = @{
        Path          = $Path
        ReferenceTime = $refTime
        DryRun        = $DryRun
    }
    if ($MaxAgeDays -gt 0)            { $invokeArgs.MaxAgeDays            = $MaxAgeDays }
    if ($KeepLatestPerWorkflow -gt 0) { $invokeArgs.KeepLatestPerWorkflow = $KeepLatestPerWorkflow }
    if ($MaxTotalSizeBytes -gt 0)     { $invokeArgs.MaxTotalSizeBytes     = $MaxTotalSizeBytes }

    $result = Invoke-ArtifactCleanup @invokeArgs

    # Human-readable report.
    Write-Host (Format-CleanupSummary -Plan $result)

    # Machine-parseable lines for the CI test harness to assert on exactly.
    Write-Host "RESULT:DRY_RUN=$($result.DryRun)"
    Write-Host "RESULT:DELETED_COUNT=$($result.Summary.DeletedCount)"
    Write-Host "RESULT:RETAINED_COUNT=$($result.Summary.RetainedCount)"
    Write-Host "RESULT:SPACE_RECLAIMED=$($result.Summary.SpaceReclaimed)"
    Write-Host "RESULT:RETAINED_SIZE=$($result.Summary.RetainedSize)"
    foreach ($item in ($result.Items | Where-Object Action -eq 'Delete' | Sort-Object Name)) {
        Write-Host "RESULT:DELETE=$($item.Name)"
    }

    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
