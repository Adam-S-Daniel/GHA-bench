#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the artifact cleanup engine. Reads a JSON "fixture"
    describing the artifacts + retention policy, computes a deletion plan, and
    prints a human-readable report plus machine-parseable result markers.

.DESCRIPTION
    This is the script the GitHub Actions workflow invokes. It keeps the CI side
    thin: all real logic lives in ArtifactCleanup.psm1 (unit-tested separately).

    Input fixture (JSON) shape:
        {
          "now":     "2026-06-28T00:00:00Z",   // reference time for age calc (optional)
          "dryRun":  true,                       // optional, default true
          "policy": {
            "maxAgeDays":        30,             // 0/absent = disabled
            "keepLatestN":       2,              // 0/absent = disabled
            "maxTotalSizeBytes": 5000            // 0/absent = disabled
          },
          "artifacts": [
            { "name": "build-1", "sizeBytes": 1000,
              "createdAt": "2026-01-01T00:00:00Z", "workflowRunId": "100" }
          ]
        }

    Output: a readable plan, followed by stable, grep-friendly markers of the
    form  ACLEANUP::<Key>=<Value>  so callers (and the act test harness) can
    assert on exact values.

.PARAMETER FixturePath
    Path to the JSON fixture. Defaults to $env:FIXTURE_PATH, then 'fixtures/case.json'.

.PARAMETER DryRun
    Force dry-run on/off, overriding the fixture's "dryRun" value.
#>
[CmdletBinding()]
param(
    [string] $FixturePath = $(if ($env:FIXTURE_PATH) { $env:FIXTURE_PATH } else { 'fixtures/case.json' }),
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the engine relative to this script so it works from any CWD.
Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

# --- Load + validate the fixture ------------------------------------------
if (-not (Test-Path -LiteralPath $FixturePath)) {
    Write-Error "Fixture file not found: '$FixturePath'. Set -FixturePath or `$env:FIXTURE_PATH."
    exit 1
}

try {
    $raw    = Get-Content -LiteralPath $FixturePath -Raw
    $config = $raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse fixture '$FixturePath' as JSON: $($_.Exception.Message)"
    exit 1
}

# Helper: read an optional property with a fallback default (StrictMode-safe).
function Get-Prop {
    param($Object, [string] $Name, $Default = $null)
    if ($null -ne $Object -and ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Object.$Name
    }
    return $Default
}

# Reference time for age calculations (deterministic when supplied by fixture).
$nowRaw = Get-Prop $config 'now' $null
$now    = if ($nowRaw) { [datetime]::Parse($nowRaw, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime() }
          else { [datetime]::UtcNow }

# Dry-run: explicit -DryRun switch wins; otherwise the fixture; default true.
$dryRunValue = if ($PSBoundParameters.ContainsKey('DryRun')) { [bool]$DryRun }
               else { [bool](Get-Prop $config 'dryRun' $true) }

# Policy values (0 / absent disables each policy).
$policy            = Get-Prop $config 'policy' $null
$maxAgeDays        = [int]  (Get-Prop $policy 'maxAgeDays'        0)
$keepLatestN       = [int]  (Get-Prop $policy 'keepLatestN'       0)
$maxTotalSizeBytes = [long] (Get-Prop $policy 'maxTotalSizeBytes' 0)

$artifacts = @(Get-Prop $config 'artifacts' @())

# --- Run the engine -------------------------------------------------------
# In live mode the delete action just announces each deletion (mock data — no
# real GitHub API call). In dry-run the action is never invoked.
$deleteAction = { param($a) Write-Host "  [DELETE] $($a.Name) ($($a.SizeBytes) bytes) reason=$($a.Reason)" }

try {
    $result = Invoke-ArtifactCleanup -Artifacts $artifacts `
        -MaxAgeDays $maxAgeDays `
        -MaxTotalSizeBytes $maxTotalSizeBytes `
        -KeepLatestN $keepLatestN `
        -Now $now `
        -DryRun:$dryRunValue `
        -DeleteAction $deleteAction
}
catch {
    Write-Error "Cleanup failed: $($_.Exception.Message)"
    exit 1
}

$summary  = $result.Summary
$policies = if ($summary.PoliciesApplied.Count -gt 0) { $summary.PoliciesApplied -join '; ' } else { '(none)' }

# --- Human-readable report ------------------------------------------------
Write-Host '=== Artifact Cleanup Plan ==='
Write-Host ("Mode:     {0}" -f $(if ($result.DryRun) { 'DRY-RUN (no deletions performed)' } else { 'LIVE (deletions executed)' }))
Write-Host ("Now:      {0:yyyy-MM-ddTHH:mm:ssZ}" -f $now)
Write-Host ("Policies: {0}" -f $policies)
Write-Host ''

Write-Host ("Artifacts to delete ({0}):" -f $summary.DeletedCount)
foreach ($a in $result.Deleted) {
    Write-Host ("  - {0} [run {1}] {2} bytes, created {3:yyyy-MM-dd} (reason: {4})" -f `
        $a.Name, $a.WorkflowRunId, $a.SizeBytes, $a.CreatedAt, $a.Reason)
}
Write-Host ''
Write-Host ("Artifacts retained ({0}):" -f $summary.RetainedCount)
foreach ($a in $result.Retained) {
    $tag = if ($a.Protected) { ' [protected]' } else { '' }
    Write-Host ("  - {0} [run {1}] {2} bytes, created {3:yyyy-MM-dd}{4}" -f `
        $a.Name, $a.WorkflowRunId, $a.SizeBytes, $a.CreatedAt, $tag)
}
Write-Host ''
Write-Host '--- Summary ---'
Write-Host ("  Total artifacts : {0}" -f $summary.TotalArtifacts)
Write-Host ("  Retained        : {0} ({1} bytes)" -f $summary.RetainedCount, $summary.RetainedSizeBytes)
Write-Host ("  Deleted         : {0} ({1} bytes)" -f $summary.DeletedCount, $summary.DeletedSizeBytes)
Write-Host ("  Space reclaimed : {0} bytes" -f $summary.SpaceReclaimedBytes)
if ($summary.OverBudget) {
    Write-Host '  WARNING: retained size still exceeds the size budget (protected artifacts).'
}
Write-Host ''

# --- Stable machine-parseable markers (for the act harness / CI) ----------
# Sets are emitted sorted by name so assertions are order-independent.
$deletedNames  = @($result.Deleted  | ForEach-Object Name | Sort-Object) -join ','
$retainedNames = @($result.Retained | ForEach-Object Name | Sort-Object) -join ','

Write-Host ("ACLEANUP::TotalArtifacts={0}"      -f $summary.TotalArtifacts)
Write-Host ("ACLEANUP::RetainedCount={0}"       -f $summary.RetainedCount)
Write-Host ("ACLEANUP::DeletedCount={0}"        -f $summary.DeletedCount)
Write-Host ("ACLEANUP::TotalSizeBytes={0}"      -f $summary.TotalSizeBytes)
Write-Host ("ACLEANUP::RetainedSizeBytes={0}"   -f $summary.RetainedSizeBytes)
Write-Host ("ACLEANUP::DeletedSizeBytes={0}"    -f $summary.DeletedSizeBytes)
Write-Host ("ACLEANUP::SpaceReclaimedBytes={0}" -f $summary.SpaceReclaimedBytes)
Write-Host ("ACLEANUP::OverBudget={0}"          -f $summary.OverBudget)
Write-Host ("ACLEANUP::DryRun={0}"              -f $result.DryRun)
Write-Host ("ACLEANUP::Executed={0}"            -f $result.Executed)
Write-Host ("ACLEANUP::DeletedNames={0}"        -f $deletedNames)
Write-Host ("ACLEANUP::RetainedNames={0}"       -f $retainedNames)
Write-Host  "ACLEANUP::Result=OK"

exit 0
