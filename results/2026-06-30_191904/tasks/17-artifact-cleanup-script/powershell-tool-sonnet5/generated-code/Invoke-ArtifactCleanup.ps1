<#
    .SYNOPSIS
    CLI entry point for the artifact cleanup pipeline. Loads an artifact
    inventory from JSON, applies retention policies, prints a plan summary,
    and (unless -DryRun) writes an updated inventory with deleted artifacts
    removed -- simulating what would happen after calling the real GitHub
    Artifacts delete API for each artifact in the Deleted set.

    .PARAMETER ArtifactsPath
    Path to a JSON file containing an array of artifact objects (Name,
    SizeBytes, CreatedAt, WorkflowName).

    .PARAMETER MaxAgeDays
    Delete artifacts older than this many days. 0 disables the policy.

    .PARAMETER MaxTotalSizeMB
    Delete the oldest artifacts first until total size is at or below this
    many megabytes. 0 disables the policy.

    .PARAMETER KeepLatestN
    Per workflow, keep only the N most recently created artifacts. 0
    disables the policy.

    .PARAMETER DryRun
    Compute and print/report the plan, but do not write a remaining-artifacts
    inventory (i.e. do not simulate performing the deletions).

    .PARAMETER Now
    Reference "current time" (ISO-8601 string) for age calculations. Defaults
    to the real current UTC time.

    .PARAMETER ScenarioName
    A label included in the machine-parseable summary line, useful when a
    single workflow run evaluates multiple scenarios (e.g. a build matrix).

    .PARAMETER PlanOutputPath
    Where to write the full JSON deletion plan. Defaults to cleanup-plan.json
    in the current directory.

    .PARAMETER RemainingOutputPath
    Where to write the updated artifact inventory (retained artifacts only)
    when not in DryRun mode. Defaults to remaining-artifacts.json in the
    current directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ArtifactsPath,

    [int] $MaxAgeDays = 0,

    [int] $MaxTotalSizeMB = 0,

    [int] $KeepLatestN = 0,

    [switch] $DryRun,

    [string] $Now,

    [string] $ScenarioName = 'default',

    [string] $PlanOutputPath = 'cleanup-plan.json',

    [string] $RemainingOutputPath = 'remaining-artifacts.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

if (-not (Test-Path -Path $ArtifactsPath)) {
    throw "Artifacts file not found at path '$ArtifactsPath'."
}

try {
    $artifacts = Get-Content -Raw -Path $ArtifactsPath | ConvertFrom-Json
}
catch {
    throw "Failed to parse artifacts file '$ArtifactsPath' as JSON: $($_.Exception.Message)"
}

# A single-object JSON file parses to a scalar PSCustomObject rather than an
# array; normalize so the policy engine always receives an array.
$artifactArray = @($artifacts)

$nowUtc = if ($Now) { [datetime]::Parse($Now, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime() } else { (Get-Date).ToUniversalTime() }

$policyParams = @{
    Artifacts = $artifactArray
    Now       = $nowUtc
}
if ($MaxAgeDays -gt 0) { $policyParams.MaxAgeDays = $MaxAgeDays }
if ($MaxTotalSizeMB -gt 0) { $policyParams.MaxTotalSizeBytes = [long]$MaxTotalSizeMB * 1MB }
if ($KeepLatestN -gt 0) { $policyParams.KeepLatestN = $KeepLatestN }
if ($DryRun) { $policyParams.DryRun = $true }

$plan = Get-ArtifactCleanupPlan @policyParams

Write-Output "Artifact cleanup plan for scenario '$ScenarioName' (reference time: $($nowUtc.ToString('o')))"
foreach ($artifact in $plan.Deleted) {
    $verb = if ($DryRun) { '[DRY-RUN DELETE]' } else { '[DELETE]' }
    Write-Output "  $verb $($artifact.Name) (reason: $($artifact.DeletionReason), size: $($artifact.SizeBytes) bytes)"
}
foreach ($artifact in $plan.Retained) {
    Write-Output "  [RETAIN] $($artifact.Name) (size: $($artifact.SizeBytes) bytes)"
}

$plan | ConvertTo-Json -Depth 6 | Set-Content -Path $PlanOutputPath
Write-Output "Deletion plan written to $PlanOutputPath"

if (-not $DryRun) {
    $plan.Retained | ForEach-Object {
        [pscustomobject]@{
            Name          = $_.Name
            SizeBytes     = $_.SizeBytes
            CreatedAt     = $_.CreatedAt
            WorkflowName  = $_.WorkflowName
            WorkflowRunId = $_.WorkflowRunId
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $RemainingOutputPath
    Write-Output "Remaining artifact inventory written to $RemainingOutputPath"
}
else {
    Write-Output '[DRY-RUN] No changes made; remaining-artifacts inventory not written.'
}

Write-Output (Format-ArtifactCleanupSummary -Plan $plan -ScenarioName $ScenarioName)
