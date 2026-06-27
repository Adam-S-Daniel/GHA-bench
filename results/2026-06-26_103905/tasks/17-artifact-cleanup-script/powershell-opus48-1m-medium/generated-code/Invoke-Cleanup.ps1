#!/usr/bin/env pwsh
<#
    Invoke-Cleanup.ps1

    Entry point used by both humans and the CI workflow. It loads artifact
    metadata and a retention policy from JSON fixtures, runs the retention engine
    in ArtifactCleanup.psm1, prints a human-readable deletion plan, and emits a
    block of machine-parseable KEY=VALUE lines that the act test harness asserts
    on.

    Fixture format (fixtures/artifacts.json):
        [ { "Name": "build", "Size": 1024, "Created": "2026-06-01T00:00:00Z",
            "WorkflowRunId": 101 }, ... ]

    Policy format (fixtures/policy.json):
        { "MaxAgeDays": 30, "MaxTotalSize": 0, "KeepLatestN": 2,
          "Now": "2026-06-26T00:00:00Z", "DryRun": true }
    Any policy field may be omitted; 0 / absent disables that policy.
#>
[CmdletBinding()]
param(
    [string]$ArtifactsPath = (Join-Path $PSScriptRoot 'fixtures/artifacts.json'),
    [string]$PolicyPath    = (Join-Path $PSScriptRoot 'fixtures/policy.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

# Read a JSON file with a clear error if it is missing or malformed.
function Read-JsonFile {
    param([string]$Path, [string]$What)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$What file not found at '$Path'."
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "$What file '$Path' is not valid JSON: $($_.Exception.Message)"
    }
}

try {
    $rawArtifacts = Read-JsonFile -Path $ArtifactsPath -What 'Artifacts'
    $policy       = Read-JsonFile -Path $PolicyPath -What 'Policy'

    # Normalise each raw record into a validated artifact object.
    $artifacts = foreach ($r in @($rawArtifacts)) {
        New-ArtifactObject -Name $r.Name -Size $r.Size -Created $r.Created -WorkflowRunId $r.WorkflowRunId
    }

    # Pull policy fields, treating absent fields as "disabled".
    $hasNow = $policy.PSObject.Properties.Name -contains 'Now'
    $now = if ($hasNow) { [datetime]::Parse($policy.Now, [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
           else { [datetime]::UtcNow }

    $get = { param($n) if ($policy.PSObject.Properties.Name -contains $n) { $policy.$n } else { 0 } }

    $plan = Invoke-ArtifactRetention -Artifacts @($artifacts) `
        -MaxAgeDays   ([int](& $get 'MaxAgeDays')) `
        -MaxTotalSize ([long](& $get 'MaxTotalSize')) `
        -KeepLatestN  ([int](& $get 'KeepLatestN')) `
        -ReferenceDate $now `
        -DryRun:([bool](& $get 'DryRun'))

    # --- Human-readable plan ---------------------------------------------------
    Write-Host '=== ARTIFACT DELETION PLAN ==='
    Write-Host ("Mode: {0}" -f ($(if ($plan.Summary.DryRun) { 'DRY-RUN (no deletions performed)' } else { 'LIVE' })))
    Write-Host ''
    Write-Host 'Artifacts to DELETE:'
    if ($plan.Deleted.Count -eq 0) {
        Write-Host '  (none)'
    } else {
        foreach ($a in ($plan.Deleted | Sort-Object WorkflowRunId)) {
            Write-Host ("  - {0} (run {1}, {2} bytes)" -f $a.Name, $a.WorkflowRunId, $a.Size)
        }
    }
    Write-Host 'Artifacts to RETAIN:'
    if ($plan.Retained.Count -eq 0) {
        Write-Host '  (none)'
    } else {
        foreach ($a in ($plan.Retained | Sort-Object WorkflowRunId)) {
            Write-Host ("  - {0} (run {1}, {2} bytes)" -f $a.Name, $a.WorkflowRunId, $a.Size)
        }
    }

    # --- Machine-parseable summary block (asserted by the act harness) ---------
    Write-Host ''
    Write-Host '=== SUMMARY ==='
    Write-Host ("DRY_RUN={0}" -f $plan.Summary.DryRun.ToString().ToLowerInvariant())
    Write-Host ("RETAINED_COUNT={0}" -f $plan.Summary.RetainedCount)
    Write-Host ("DELETED_COUNT={0}" -f $plan.Summary.DeletedCount)
    Write-Host ("SPACE_RECLAIMED={0}" -f $plan.Summary.SpaceReclaimed)
    # Stable, sorted list of deleted run ids for exact assertions.
    $ids = ($plan.Deleted | Sort-Object WorkflowRunId | ForEach-Object { $_.WorkflowRunId }) -join ','
    Write-Host ("DELETED_RUN_IDS={0}" -f $ids)
    Write-Host '=== END ==='

    exit 0
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
