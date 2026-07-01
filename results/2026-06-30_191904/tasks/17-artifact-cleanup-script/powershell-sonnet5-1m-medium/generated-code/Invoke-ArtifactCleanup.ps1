#requires -Version 7.0
<#
    .SYNOPSIS
    CI entry point for artifact cleanup. Loads artifact metadata from a JSON
    file, applies retention policies, and prints a deletion plan + summary.

    .PARAMETER ArtifactsPath
    Path to a JSON file containing an array of artifact records, each with
    Name, SizeBytes, CreatedAt, WorkflowRunId, WorkflowName.

    .PARAMETER MaxAgeDays
    Delete artifacts older than this many days. 0 disables the policy.

    .PARAMETER MaxTotalSizeBytes
    Trim the oldest retained artifacts until total size is under this
    budget. 0 disables the policy.

    .PARAMETER KeepLatestN
    Keep only the N most recently created artifacts per workflow. 0
    disables the policy.

    .PARAMETER Now
    ISO-8601 timestamp to use as "now" for age calculations. Defaults to the
    current time; CI passes a fixed value so output is reproducible.

    .PARAMETER DryRun
    Report what would be deleted without deleting anything.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactsPath,

    [int]$MaxAgeDays = 0,

    [long]$MaxTotalSizeBytes = 0,

    [int]$KeepLatestN = 0,

    [string]$Now,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/ArtifactCleanup.psm1" -Force

if (-not (Test-Path -Path $ArtifactsPath)) {
    throw "Artifacts file not found: '$ArtifactsPath'."
}

try {
    $artifacts = @(Get-Content -Raw -Path $ArtifactsPath | ConvertFrom-Json)
} catch {
    throw "Failed to parse artifacts JSON at '$ArtifactsPath': $($_.Exception.Message)"
}

$nowValue = if ($Now) { [datetime]$Now } else { Get-Date }

$result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays $MaxAgeDays -MaxTotalSizeBytes $MaxTotalSizeBytes -KeepLatestN $KeepLatestN -Now $nowValue -DryRun:$DryRun

Write-Output 'CLEANUP SUMMARY'
Write-Output "TotalArtifacts=$($result.TotalArtifacts)"
Write-Output "RetainedCount=$($result.RetainedCount)"
Write-Output "DeletedCount=$($result.DeletedCount)"
Write-Output "SpaceReclaimedBytes=$($result.SpaceReclaimedBytes)"
Write-Output "SpaceRetainedBytes=$($result.SpaceRetainedBytes)"
Write-Output "DryRun=$($result.DryRun)"
