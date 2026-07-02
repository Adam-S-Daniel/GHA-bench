<#
.SYNOPSIS
    CLI entry point for the CI artifact cleanup planner.
.DESCRIPTION
    Loads artifact metadata (mock data) from a JSON file, applies the retention
    policies (max age, max total size, keep-latest-N per workflow run), and
    prints a deletion plan plus a machine-parseable summary as RESULT lines.

    In -DryRun mode nothing is "deleted"; the plan is only reported. Without
    -DryRun each planned deletion is executed via a deleter (here a mock that
    logs the deletion, standing in for a real artifact-API call).
.EXAMPLE
    ./Invoke-ArtifactCleanup.ps1 -ArtifactsPath tests/fixtures/sample-artifacts.json `
        -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -MaxTotalSizeBytes 157286400 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactsPath,

    [Nullable[int]]$MaxAgeDays,

    [Nullable[int]]$KeepLatestPerWorkflow,

    [Nullable[long]]$MaxTotalSizeBytes,

    # Fixed "now" for deterministic runs (tests/CI); defaults to real UTC now.
    [string]$ReferenceDate,

    # Where to write the full plan as JSON (optional).
    [string]$PlanPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src' 'ArtifactCleanup.psm1') -Force

# --- Load and validate input -------------------------------------------------
if (-not (Test-Path -LiteralPath $ArtifactsPath)) {
    throw "Artifacts file not found: '$ArtifactsPath'. Provide a JSON file with artifact metadata."
}

try {
    $artifacts = Get-Content -LiteralPath $ArtifactsPath -Raw | ConvertFrom-Json
}
catch {
    throw "Artifacts file '$ArtifactsPath' is not valid JSON: $($_.Exception.Message)"
}
$artifacts = @($artifacts)

$refDate = if ($ReferenceDate) {
    [datetime]::Parse($ReferenceDate, [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AdjustToUniversal)
} else {
    (Get-Date).ToUniversalTime()
}

# --- Build the plan ----------------------------------------------------------
$planParams = @{ Artifacts = $artifacts; ReferenceDate = $refDate }
if ($null -ne $MaxAgeDays)            { $planParams.MaxAgeDays            = $MaxAgeDays }
if ($null -ne $KeepLatestPerWorkflow) { $planParams.KeepLatestPerWorkflow = $KeepLatestPerWorkflow }
if ($null -ne $MaxTotalSizeBytes)     { $planParams.MaxTotalSizeBytes     = $MaxTotalSizeBytes }

$plan = Get-ArtifactCleanupPlan @planParams

# --- Report the plan ---------------------------------------------------------
Write-Output "Artifact cleanup plan (reference date: $($refDate.ToString('u')))"
foreach ($artifact in $plan.Deleted) {
    Write-Output "DELETE $($artifact.Name) reason=$($artifact.Reason) size=$($artifact.SizeBytes)"
}
foreach ($artifact in $plan.Retained) {
    Write-Output "RETAIN $($artifact.Name) size=$($artifact.SizeBytes)"
}

# --- Execute (or dry-run) ----------------------------------------------------
# The deleter is a mock: with real data this would call the artifact store
# API. It logs to a list (not the pipeline) so the summary object returned by
# Invoke-ArtifactCleanup stays clean.
$deletionLog = [System.Collections.Generic.List[string]]::new()
$deleter = { param($artifact)
    $deletionLog.Add("Deleted artifact '$($artifact.Name)' ($($artifact.SizeBytes) bytes)")
}.GetNewClosure()

$result = Invoke-ArtifactCleanup -Plan $plan -Deleter $deleter -DryRun:$DryRun
$deletionLog | Write-Output

# --- Machine-parseable summary (asserted exactly by tests and the act harness)
$mode = if ($DryRun) { 'DRY-RUN' } else { 'EXECUTE' }
Write-Output "RESULT Mode=$mode"
Write-Output "RESULT TotalArtifacts=$($result.TotalArtifacts)"
Write-Output "RESULT DeletedCount=$($result.DeletedCount)"
Write-Output "RESULT RetainedCount=$($result.RetainedCount)"
Write-Output "RESULT SpaceReclaimedBytes=$($result.SpaceReclaimedBytes)"
Write-Output "RESULT RetainedSizeBytes=$($result.RetainedSizeBytes)"

if ($PlanPath) {
    $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PlanPath -Encoding utf8
    Write-Output "Plan written to $PlanPath"
}
