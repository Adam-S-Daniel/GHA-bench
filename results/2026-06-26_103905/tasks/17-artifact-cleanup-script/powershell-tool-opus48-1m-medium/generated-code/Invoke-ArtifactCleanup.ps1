#!/usr/bin/env pwsh
#
# Invoke-ArtifactCleanup.ps1
#
# Command-line front end around Get-ArtifactCleanupPlan. It reads a JSON
# fixture describing the artifacts and the retention policies to apply, runs
# the planner, and prints both a human-readable report and a set of stable,
# machine-parseable lines that CI can assert on exactly.
#
# Fixture JSON shape:
#   {
#     "now":      "2026-06-01T00:00:00Z",      # optional reference time (UTC)
#     "dryRun":   true,                          # optional, default false
#     "policies": { "maxAgeDays": 30,
#                   "keepLatestN": 2,
#                   "maxTotalSizeBytes": 0 },    # any field optional / 0 = off
#     "artifacts": [
#       { "name": "...", "sizeBytes": 100,
#         "createdAt": "2026-05-01T00:00:00Z", "workflowRunId": 1 }
#     ]
#   }
#
# Exit codes:
#   0  plan produced successfully
#   1  bad input / processing error (message written to stderr)

[CmdletBinding()]
param(
    # Path to the JSON fixture. Required.
    [Parameter(Mandatory)]
    [string] $InputPath,

    # Force dry-run regardless of the fixture's dryRun flag.
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the planning module that lives alongside this script.
$here = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $here 'ArtifactCleanup.psm1') -Force

function Write-Stamped {
    # Machine-parseable output uses a leading tag so CI can grep precisely.
    param([string] $Line)
    Write-Output $Line
}

try {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input fixture not found: '$InputPath'."
    }

    $raw = Get-Content -LiteralPath $InputPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Input fixture '$InputPath' is empty."
    }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw "Input fixture '$InputPath' is not valid JSON: $($_.Exception.Message)"
    }

    # --- Resolve reference time ---------------------------------------
    $now =
        if ($data.PSObject.Properties.Name -contains 'now' -and $data.now) {
            [datetime]::Parse($data.now, [cultureinfo]::InvariantCulture,
                              [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        } else {
            [datetime]::UtcNow
        }

    # --- Resolve policies (all optional) ------------------------------
    $policies = if ($data.PSObject.Properties.Name -contains 'policies') { $data.policies } else { $null }
    $getPolicy = {
        param($name)
        if ($policies -and ($policies.PSObject.Properties.Name -contains $name) -and $null -ne $policies.$name) {
            return $policies.$name
        }
        return 0
    }
    $maxAgeDays        = [int]  (& $getPolicy 'maxAgeDays')
    $keepLatestN       = [int]  (& $getPolicy 'keepLatestN')
    $maxTotalSizeBytes = [long] (& $getPolicy 'maxTotalSizeBytes')

    # --- Resolve dry-run ----------------------------------------------
    $isDryRun = $DryRun.IsPresent
    if (-not $isDryRun -and ($data.PSObject.Properties.Name -contains 'dryRun')) {
        $isDryRun = [bool]$data.dryRun
    }

    # --- Map artifacts -------------------------------------------------
    if (-not ($data.PSObject.Properties.Name -contains 'artifacts') -or $null -eq $data.artifacts) {
        throw "Input fixture must contain an 'artifacts' array."
    }
    $artifacts = @(
        foreach ($a in $data.artifacts) {
            [pscustomobject]@{
                Name          = $a.name
                SizeBytes     = [long]$a.sizeBytes
                CreatedAt     = [datetime]::Parse($a.createdAt, [cultureinfo]::InvariantCulture,
                                    [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                WorkflowRunId = $a.workflowRunId
            }
        }
    )

    # --- Build the plan ------------------------------------------------
    $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts `
        -MaxAgeDays $maxAgeDays -KeepLatestN $keepLatestN `
        -MaxTotalSizeBytes $maxTotalSizeBytes -Now $now -DryRun:$isDryRun

    $s = $plan.Summary

    # --- Human-readable report ----------------------------------------
    Write-Output ''
    Write-Output '=== Artifact Cleanup Plan ==='
    Write-Output ("Mode            : {0}" -f $(if ($plan.DryRun) { 'DRY-RUN (no deletions performed)' } else { 'EXECUTE' }))
    Write-Output ("Policies        : maxAgeDays={0} keepLatestN={1} maxTotalSizeBytes={2}" -f `
            $maxAgeDays, $keepLatestN, $maxTotalSizeBytes)
    Write-Output ("Total artifacts : {0}" -f $s.TotalArtifacts)
    Write-Output ("To delete       : {0}" -f $s.DeletedCount)
    Write-Output ("To retain       : {0}" -f $s.RetainedCount)
    Write-Output ("Space reclaimed : {0} bytes" -f $s.SpaceReclaimedBytes)
    Write-Output ("Retained size   : {0} bytes" -f $s.RetainedSizeBytes)
    Write-Output ''
    if ($s.DeletedCount -gt 0) {
        Write-Output 'Artifacts to delete:'
        foreach ($d in ($plan.ToDelete | Sort-Object Name)) {
            Write-Output ("  - {0} ({1} bytes) :: {2}" -f $d.Name, $d.SizeBytes, $d.Reason)
        }
        Write-Output ''
    }

    # --- Stable machine-parseable lines (for CI assertions) -----------
    Write-Stamped ("PLAN_SUMMARY total={0} deleted={1} retained={2} reclaimedBytes={3} retainedBytes={4} dryRun={5}" -f `
            $s.TotalArtifacts, $s.DeletedCount, $s.RetainedCount, `
            $s.SpaceReclaimedBytes, $s.RetainedSizeBytes, $plan.DryRun.ToString().ToLower())
    foreach ($d in ($plan.ToDelete | Sort-Object Name)) {
        Write-Stamped ("DELETE name={0} sizeBytes={1}" -f $d.Name, $d.SizeBytes)
    }
    foreach ($r in ($plan.ToRetain | Sort-Object Name)) {
        Write-Stamped ("RETAIN name={0} sizeBytes={1}" -f $r.Name, $r.SizeBytes)
    }
    Write-Stamped 'PLAN_COMPLETE'

    exit 0
}
catch {
    Write-Error "artifact-cleanup failed: $($_.Exception.Message)"
    exit 1
}
