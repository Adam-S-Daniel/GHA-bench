<#
    .SYNOPSIS
        CLI entry point that runs an artifact cleanup pass from a JSON
        scenario file (mock artifact metadata + retention policy) and prints
        a human-readable, machine-parseable deletion plan report.

    .DESCRIPTION
        This is the script a GitHub Actions workflow step invokes. It loads
        mock artifact data from -ConfigPath, applies the retention policies
        embedded in that file via the ArtifactCleanup module, and reports:
          - how many artifacts would be / were deleted
          - how much space was reclaimed
          - how many artifacts were actually removed (0 in dry-run mode)

        All decision logic lives in ArtifactCleanup.psm1; this script is just
        the JSON-in / report-out wrapper plus error handling for bad input.

    .EXAMPLE
        ./artifact-cleanup.ps1 -ConfigPath ./fixtures/scenario-age-and-keep-latest.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ConfigPath,

    # When set, forces dry-run regardless of the config file's own dryRun
    # value. Useful for a manual "preview only" workflow_dispatch run.
    [switch] $ForceDryRun
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'ArtifactCleanup.psm1'
Import-Module $modulePath -Force

function Write-CleanupReport {
    param($ScenarioName, $ReferenceDate, $Policy, $Result)

    $plan = $Result.Plan
    $summary = $plan.Summary

    Write-Output "##### Artifact Cleanup Report: $ScenarioName #####"
    Write-Output "ReferenceDate: $($ReferenceDate.ToString('o'))"
    Write-Output "DryRun: $($Result.DryRun)"
    Write-Output "Policy: MaxAgeDays=$($Policy.MaxAgeDays) MaxTotalSizeBytes=$($Policy.MaxTotalSizeBytes) KeepLatestPerWorkflow=$($Policy.KeepLatestPerWorkflow)"
    Write-Output "TotalArtifacts: $($summary.TotalArtifacts)"
    Write-Output "Deleted: $($summary.DeletedCount)"
    Write-Output "Retained: $($summary.RetainedCount)"
    Write-Output "BytesReclaimed: $($summary.BytesReclaimed)"
    Write-Output "ArtifactsActuallyRemoved: $($Result.ArtifactsActuallyRemoved)"
    Write-Output '--- Deleted Artifacts ---'
    foreach ($item in $plan.ToDelete) {
        Write-Output "$($item.Name) ($($item.SizeBytes) bytes, reason: $($item.Reason))"
    }
    Write-Output '--- Retained Artifacts ---'
    foreach ($item in $plan.ToRetain) {
        Write-Output "$($item.Name) ($($item.SizeBytes) bytes, reason: $($item.Reason))"
    }
    Write-Output "##### End Report: $ScenarioName #####"

    if ($env:GITHUB_STEP_SUMMARY) {
        $lines = @(
            "### Artifact Cleanup Report: $ScenarioName"
            "- DryRun: $($Result.DryRun)"
            "- TotalArtifacts: $($summary.TotalArtifacts)"
            "- Deleted: $($summary.DeletedCount)"
            "- Retained: $($summary.RetainedCount)"
            "- BytesReclaimed: $($summary.BytesReclaimed)"
            "- ArtifactsActuallyRemoved: $($Result.ArtifactsActuallyRemoved)"
        )
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n")
    }
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: '$ConfigPath'."
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        throw "Config file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    if (-not $config.artifacts) {
        throw "Config file '$ConfigPath' has no 'artifacts' array."
    }

    $referenceDate = if ($config.referenceDate) { ConvertTo-UtcDateTime -Value $config.referenceDate } else { (Get-Date).ToUniversalTime() }
    $policy = $config.policy
    $maxAgeDays = if ($policy.maxAgeDays) { [int]$policy.maxAgeDays } else { 0 }
    $maxTotalSizeBytes = if ($policy.maxTotalSizeBytes) { [long]$policy.maxTotalSizeBytes } else { 0 }
    $keepLatestPerWorkflow = if ($policy.keepLatestPerWorkflow) { [int]$policy.keepLatestPerWorkflow } else { 0 }
    $dryRun = [bool]$ForceDryRun -or [bool]$config.dryRun

    $artifacts = @()
    for ($i = 0; $i -lt $config.artifacts.Count; $i++) {
        try {
            $artifacts += ConvertTo-ArtifactObject -Raw $config.artifacts[$i]
        } catch {
            throw "Config file '$ConfigPath', artifacts[$i]: $($_.Exception.Message)"
        }
    }

    $result = Invoke-ArtifactCleanup -Artifact $artifacts -MaxAgeDays $maxAgeDays `
        -MaxTotalSizeBytes $maxTotalSizeBytes -KeepLatestPerWorkflow $keepLatestPerWorkflow `
        -ReferenceDate $referenceDate -DryRun:$dryRun

    $scenarioName = if ($config.scenarioName) { $config.scenarioName } else { [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath) }
    $policyForReport = [PSCustomObject]@{
        MaxAgeDays            = $maxAgeDays
        MaxTotalSizeBytes     = $maxTotalSizeBytes
        KeepLatestPerWorkflow = $keepLatestPerWorkflow
    }
    Write-CleanupReport -ScenarioName $scenarioName -ReferenceDate $referenceDate -Policy $policyForReport -Result $result

    exit 0
} catch {
    Write-Error "Artifact cleanup failed: $($_.Exception.Message)"
    exit 1
}
