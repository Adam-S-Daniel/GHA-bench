#!/usr/bin/env pwsh
#
# Invoke-ArtifactCleanup.ps1
#
# Entry point used by the GitHub Actions workflow. Loads mock artifact
# metadata, applies retention policies, and prints a deletion plan plus a
# machine-parseable KEY=VALUE summary (so the workflow / tests can assert
# on exact values without scraping prose).
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FixturePath,

    [Parameter(Mandatory = $true)]
    [int]$MaxAgeDays,

    [Parameter(Mandatory = $true)]
    [int64]$MaxTotalSizeBytes,

    [Parameter(Mandatory = $true)]
    [int]$KeepLatestN,

    # Overridable so runs are deterministic in tests/CI; defaults to real time.
    [string]$Now,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

    $nowValue = if ($Now) { [datetime]::Parse($Now).ToUniversalTime() } else { (Get-Date).ToUniversalTime() }

    $artifacts = Import-ArtifactData -Path $FixturePath
    $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays $MaxAgeDays `
        -MaxTotalSizeBytes $MaxTotalSizeBytes -KeepLatestN $KeepLatestN -Now $nowValue

    Write-Host "Artifact Cleanup Plan (DryRun: $([bool]$DryRun))"
    Write-Host '-------------------------------------------'

    Invoke-ArtifactCleanup -Plan $plan -DryRun:$DryRun | Out-Null

    Write-Host '-------------------------------------------'
    Write-Host "Summary: total=$($plan.Summary.TotalArtifacts) retained=$($plan.Summary.RetainedCount) deleted=$($plan.Summary.DeletedCount) spaceReclaimedBytes=$($plan.Summary.SpaceReclaimedBytes)"

    # Machine-parseable lines for CI assertions / job summaries.
    Write-Host "DRY_RUN=$([bool]$DryRun)"
    Write-Host "TOTAL_ARTIFACTS=$($plan.Summary.TotalArtifacts)"
    Write-Host "DELETED_COUNT=$($plan.Summary.DeletedCount)"
    Write-Host "RETAINED_COUNT=$($plan.Summary.RetainedCount)"
    Write-Host "SPACE_RECLAIMED_BYTES=$($plan.Summary.SpaceReclaimedBytes)"
    Write-Host "REMAINING_SIZE_BYTES=$($plan.Summary.RemainingSizeBytes)"

    if ($env:GITHUB_STEP_SUMMARY) {
        $lines = @(
            '## Artifact Cleanup Plan'
            ''
            "- Dry run: $([bool]$DryRun)"
            "- Total artifacts: $($plan.Summary.TotalArtifacts)"
            "- Retained: $($plan.Summary.RetainedCount)"
            "- Deleted: $($plan.Summary.DeletedCount)"
            "- Space reclaimed: $($plan.Summary.SpaceReclaimedBytes) bytes"
        )
        $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }

    exit 0
} catch {
    [Console]::Error.WriteLine("Artifact cleanup failed: $($_.Exception.Message)")
    exit 1
}
