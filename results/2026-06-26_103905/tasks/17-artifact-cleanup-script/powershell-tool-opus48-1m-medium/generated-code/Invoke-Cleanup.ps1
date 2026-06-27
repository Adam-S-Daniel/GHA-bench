#!/usr/bin/env pwsh
# Invoke-Cleanup.ps1
# Thin CLI wrapper around the ArtifactCleanup engine. Reads artifact metadata
# and retention policy from a JSON fixture, computes a deletion plan, and prints
# a parseable report. In a real pipeline the -DryRun switch (default) means
# nothing is deleted; -Execute would be where actual deletion calls go.

[CmdletBinding()]
param(
    # Path to a JSON fixture: { policy{...}, now?, artifacts[...] }.
    [Parameter(Mandatory)] [string] $FixturePath,
    # Dry-run is the safe default. -Execute flips it off (no real deletion is
    # wired up here since artifacts are mock data, but the flag is honored).
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the engine relative to this script so it works from any CWD.
Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

if (-not (Test-Path -LiteralPath $FixturePath)) {
    throw "Fixture file not found: $FixturePath"
}

try {
    $raw = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
} catch {
    throw "Failed to parse fixture '$FixturePath' as JSON: $($_.Exception.Message)"
}

if (-not ($raw.PSObject.Properties.Name -contains 'artifacts')) {
    throw "Fixture '$FixturePath' must contain an 'artifacts' array."
}

# Map JSON (camelCase) into the engine's expected artifact shape.
$artifacts = @(
    foreach ($a in $raw.artifacts) {
        [pscustomobject]@{
            Name          = $a.name
            Size          = [long]$a.size
            CreationDate  = [datetime]$a.creationDate
            WorkflowRunId = [string]$a.workflowRunId
        }
    }
)

# Resolve policy with disabled-by-default (0) semantics.
$policy = if ($raw.PSObject.Properties.Name -contains 'policy') { $raw.policy } else { [pscustomobject]@{} }
function Get-PolicyValue($obj, $name, $default) {
    if ($obj.PSObject.Properties.Name -contains $name -and $null -ne $obj.$name) { return $obj.$name }
    return $default
}
$maxAgeDays   = [int] (Get-PolicyValue $policy 'maxAgeDays' 0)
$maxTotalSize = [long](Get-PolicyValue $policy 'maxTotalSize' 0)
$keepLatest   = [int] (Get-PolicyValue $policy 'keepLatestPerWorkflow' 0)

# Allow the fixture to pin "now" for deterministic age math (else real clock).
$now = if ($raw.PSObject.Properties.Name -contains 'now' -and $raw.now) {
    [datetime]$raw.now
} else {
    Get-Date
}

$plan = New-ArtifactCleanupPlan -Artifacts $artifacts `
    -MaxAgeDays $maxAgeDays -MaxTotalSize $maxTotalSize `
    -KeepLatestPerWorkflow $keepLatest -Now $now

$report = Format-CleanupReport -Plan $plan -DryRun:(-not $Execute)
Write-Output $report
