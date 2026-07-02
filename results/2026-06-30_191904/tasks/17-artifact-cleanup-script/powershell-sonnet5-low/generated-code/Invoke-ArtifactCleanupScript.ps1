# Invoke-ArtifactCleanupScript.ps1
# Entry point for CI: loads mock artifact data, applies retention policies,
# and prints a cleanup report. Supports -DryRun to preview without deleting.

[CmdletBinding()]
param(
    [int]$MaxAgeDays = 30,
    [int]$KeepLatestN = 2,
    [long]$MaxTotalSizeBytes = 400MB,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/ArtifactCleanup.psm1" -Force
Import-Module "$PSScriptRoot/MockArtifacts.psm1" -Force

try {
    $now = Get-Date
    $artifacts = Get-MockArtifacts -Now $now

    $deleteAction = {
        param($artifact)
        Write-Verbose "Deleting artifact '$($artifact.Name)'"
    }

    $result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays $MaxAgeDays -KeepLatestN $KeepLatestN -MaxTotalSizeBytes $MaxTotalSizeBytes -Now $now -DryRun:$DryRun -DeleteAction $deleteAction

    $report = Format-CleanupReport -Plan $result.Plan -DryRun:$DryRun
    Write-Output $report
}
catch {
    Write-Error "Artifact cleanup failed: $($_.Exception.Message)"
    exit 1
}
