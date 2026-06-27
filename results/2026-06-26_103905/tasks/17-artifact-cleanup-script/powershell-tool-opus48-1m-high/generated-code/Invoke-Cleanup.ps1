#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI front-end for the artifact cleanup engine. Used by CI and humans alike.

.DESCRIPTION
    Loads artifacts from a JSON fixture, applies the supplied retention policies
    via the ArtifactCleanup module, prints a human-readable plan plus stable
    RESULT_* lines, and (unless -DryRun) "deletes" each artifact through a mock
    delete action that simply logs it (no external service required).

    Policy parameters may be passed as switches or, for CI convenience, via the
    environment variables MAX_AGE_DAYS / KEEP_LATEST / MAX_TOTAL_SIZE / DRY_RUN.
    Explicit parameters win over environment variables.

.PARAMETER FixturePath
    Path to the JSON file describing the artifacts to evaluate.

.EXAMPLE
    ./Invoke-Cleanup.ps1 -FixturePath fixtures/artifacts.json -MaxAgeDays 30 -DryRun
#>
[CmdletBinding()]
param(
    [string] $FixturePath,
    [Nullable[int]]  $MaxAgeDays,
    [Nullable[int]]  $KeepLatestPerWorkflow,
    [Nullable[long]] $MaxTotalSize,
    [Nullable[bool]] $DryRun,
    # Reference "now" for age math; defaults to current UTC. Overridable so CI
    # fixtures with fixed timestamps produce deterministic, assertable output.
    [Nullable[datetime]] $ReferenceDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    Import-Module (Join-Path $here 'ArtifactCleanup.psm1') -Force

    # --- Resolve effective settings (param > env var > default) ---------------
    if (-not $FixturePath) {
        $FixturePath = if ($env:FIXTURE_PATH) { $env:FIXTURE_PATH }
                       else { Join-Path $here 'fixtures/artifacts.json' }
    }
    if ($null -eq $MaxAgeDays -and $env:MAX_AGE_DAYS) { $MaxAgeDays = [int]$env:MAX_AGE_DAYS }
    if ($null -eq $KeepLatestPerWorkflow -and $env:KEEP_LATEST) { $KeepLatestPerWorkflow = [int]$env:KEEP_LATEST }
    if ($null -eq $MaxTotalSize -and $env:MAX_TOTAL_SIZE) { $MaxTotalSize = [long]$env:MAX_TOTAL_SIZE }
    if ($null -eq $DryRun -and $env:DRY_RUN) { $DryRun = [System.Convert]::ToBoolean($env:DRY_RUN) }
    if ($null -eq $ReferenceDate -and $env:REFERENCE_DATE) {
        $ReferenceDate = [datetime]::Parse($env:REFERENCE_DATE,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
            [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    }

    # Apply defaults for anything still unset.
    $age   = if ($null -ne $MaxAgeDays) { $MaxAgeDays } else { 0 }
    $keep  = if ($null -ne $KeepLatestPerWorkflow) { $KeepLatestPerWorkflow } else { 0 }
    $cap   = if ($null -ne $MaxTotalSize) { $MaxTotalSize } else { 0 }
    $dry   = if ($null -ne $DryRun) { [bool]$DryRun } else { $false }
    $refDt = if ($null -ne $ReferenceDate) { $ReferenceDate } else { [datetime]::UtcNow }

    Write-Host "Loading artifacts from: $FixturePath"
    Write-Host ("Policies -> MaxAgeDays={0} KeepLatestPerWorkflow={1} MaxTotalSize={2} DryRun={3}" -f `
        $age, $keep, $cap, $dry)
    Write-Host ''

    $artifacts = Import-ArtifactFixture -Path $FixturePath

    # Mock delete action: a real implementation would call the artifacts API.
    $deleteAction = { param($d) Write-Host "  DELETED: $($d.Name) ($($d.Size) bytes)" }

    $plan = Invoke-ArtifactCleanup -Artifacts $artifacts `
        -MaxAgeDays $age `
        -KeepLatestPerWorkflow $keep `
        -MaxTotalSize $cap `
        -ReferenceDate $refDt `
        -DryRun:$dry `
        -DeleteAction $deleteAction

    Write-Host ''
    Write-Host (Format-DeletionPlanSummary -Plan $plan)
    exit 0
}
catch {
    Write-Error "Artifact cleanup failed: $($_.Exception.Message)"
    exit 1
}
