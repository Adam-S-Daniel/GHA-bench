#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the artifact cleanup tool. Reads a "scenario" JSON file
    (retention policy + reference time + mock artifacts), applies the policies,
    and prints a deletion plan and summary in a machine-parseable form.

.DESCRIPTION
    Scenario JSON shape:
      {
        "now":     "2026-06-27T00:00:00Z",     # optional reference time (defaults to UtcNow)
        "dryRun":  true,                          # optional; can be overridden by -DryRun
        "policy":  { "maxAgeDays": 7, "keepLatestN": 2, "maxTotalSizeBytes": 1000 },
        "artifacts": [ { "name": ..., "sizeBytes": ..., "createdAt": ...,
                         "workflowName": ..., "workflowRunId": ... }, ... ]
      }

    Output is emitted with stable, greppable prefixes (SUMMARY:, DELETE:, RETAIN:)
    so a CI pipeline can assert on exact values.

.EXAMPLE
    ./Invoke-Cleanup.ps1 -ScenarioPath fixtures/basic.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ScenarioPath,
    # When supplied, forces dry-run regardless of the scenario's own dryRun flag.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# Import the core library from the same directory as this script.
Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

# --- Load and validate the scenario file ------------------------------------
if (-not (Test-Path -LiteralPath $ScenarioPath)) {
    Write-Error "Scenario file not found: $ScenarioPath"
    exit 1
}

try {
    $scenario = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse scenario JSON '$ScenarioPath': $($_.Exception.Message)"
    exit 1
}

if ($null -eq $scenario.artifacts) {
    Write-Error "Scenario '$ScenarioPath' has no 'artifacts' array."
    exit 1
}

try {
    $artifacts = @(ConvertTo-Artifact -InputObject $scenario.artifacts)
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Reference time: scenario.now if present, otherwise the current UTC time.
$now = if ($scenario.now) {
    [datetime]::Parse($scenario.now, $null, 'AdjustToUniversal,AssumeUniversal')
} else {
    [datetime]::UtcNow
}

# Dry-run is on if the switch was passed OR the scenario requests it.
$effectiveDryRun = $DryRun.IsPresent -or ([bool]$scenario.dryRun)

# --- Build argument splat from whichever policy fields are present -----------
$cleanupArgs = @{ Artifacts = $artifacts; Now = $now }
if ($effectiveDryRun) { $cleanupArgs['DryRun'] = $true }

$policy = $scenario.policy
if ($policy) {
    if ($null -ne $policy.maxAgeDays)        { $cleanupArgs['MaxAgeDays']        = [int]$policy.maxAgeDays }
    if ($null -ne $policy.keepLatestN)       { $cleanupArgs['KeepLatestN']       = [int]$policy.keepLatestN }
    if ($null -ne $policy.maxTotalSizeBytes) { $cleanupArgs['MaxTotalSizeBytes'] = [long]$policy.maxTotalSizeBytes }
}

# A simple deletion "executor" for non-dry-run mode. With mock data we just log
# the action; a real implementation would call the GitHub API here.
$cleanupArgs['OnDelete'] = { param($a) Write-Host "EXECUTED-DELETE: $($a.Name)" }

$result = Invoke-ArtifactCleanup @cleanupArgs

# --- Report -----------------------------------------------------------------
$mode = if ($result.DryRun) { 'DRY-RUN' } else { 'EXECUTE' }
Write-Host "=== Artifact Cleanup Plan ($mode) ==="

$s = $result.Summary
Write-Host "SUMMARY: mode=$mode totalArtifacts=$($s.TotalArtifacts) deleted=$($s.DeletedCount) retained=$($s.RetainedCount) reclaimedBytes=$($s.SpaceReclaimedBytes) retainedBytes=$($s.SpaceRetainedBytes)"

foreach ($a in $result.Plan.Delete) {
    Write-Host "DELETE: $($a.Name) sizeBytes=$($a.SizeBytes) workflow=$($a.WorkflowName) reason=`"$($a.Reason)`""
}
foreach ($a in $result.Plan.Retain) {
    Write-Host "RETAIN: $($a.Name) sizeBytes=$($a.SizeBytes) workflow=$($a.WorkflowName)"
}

Write-Host "DONE: artifact cleanup completed successfully"
exit 0
