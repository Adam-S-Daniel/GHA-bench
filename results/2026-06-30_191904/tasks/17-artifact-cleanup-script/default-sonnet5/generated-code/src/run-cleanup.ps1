<#
.SYNOPSIS
    CLI entry point for the artifact cleanup engine.

.DESCRIPTION
    Loads a JSON configuration describing a set of mock artifacts and a
    retention policy, computes a deletion plan, (optionally) "executes" it in
    dry-run mode, and prints a deterministic summary report to stdout.

    Config schema:
    {
      "now": "2026-07-01T00:00:00Z",
      "dryRun": false,
      "policy": { "maxAgeDays": 30, "maxTotalSizeBytes": 1000000000, "keepLatestN": 2 },
      "artifacts": [
        { "id": "...", "name": "...", "sizeBytes": 123, "createdAt": "...",
          "workflowName": "...", "workflowRunId": "..." }
      ]
    }

.PARAMETER ConfigPath
    Path to the JSON configuration file described above.
#>
param(
    [Parameter(Mandatory)] [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/ArtifactCleanup.psm1" -Force

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath"
}

$rawJson = Get-Content -LiteralPath $ConfigPath -Raw
try {
    $config = $rawJson | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Failed to parse JSON config at '$ConfigPath': $($_.Exception.Message)"
}

foreach ($requiredTopLevel in @('now', 'policy', 'artifacts')) {
    if (-not ($config.PSObject.Properties.Name -contains $requiredTopLevel)) {
        throw "Invalid config at '$ConfigPath': missing required top-level field '$requiredTopLevel'."
    }
}

foreach ($requiredPolicyField in @('maxAgeDays', 'maxTotalSizeBytes', 'keepLatestN')) {
    if (-not ($config.policy.PSObject.Properties.Name -contains $requiredPolicyField)) {
        throw "Invalid config at '$ConfigPath': missing required policy field '$requiredPolicyField'."
    }
}

$requiredArtifactFields = @('id', 'name', 'sizeBytes', 'createdAt', 'workflowName', 'workflowRunId')
$artifacts = for ($i = 0; $i -lt $config.artifacts.Count; $i++) {
    $raw = $config.artifacts[$i]
    foreach ($field in $requiredArtifactFields) {
        if (-not ($raw.PSObject.Properties.Name -contains $field)) {
            throw "Invalid config at '$ConfigPath': artifacts[$i] is missing required field '$field'."
        }
    }
    [PSCustomObject]@{
        Id            = [string]$raw.id
        Name          = [string]$raw.name
        SizeBytes     = [long]$raw.sizeBytes
        CreatedAt     = [datetime]$raw.createdAt
        WorkflowName  = [string]$raw.workflowName
        WorkflowRunId = [string]$raw.workflowRunId
    }
}

$now = [datetime]$config.now
$dryRun = [bool]$config.dryRun

$plan = New-RetentionPlan -Artifacts @($artifacts) `
    -MaxAgeDays $config.policy.maxAgeDays `
    -MaxTotalSizeBytes $config.policy.maxTotalSizeBytes `
    -KeepLatestN $config.policy.keepLatestN `
    -Now $now

$deleteAction = {
    param($artifact)
    Write-Verbose "Deleting artifact '$($artifact.Id)' ($($artifact.Name), $($artifact.SizeBytes) bytes)"
}

$null = Invoke-ArtifactCleanup -Plan $plan -DryRun:$dryRun -DeleteAction $deleteAction

$summary = Format-RetentionSummary -Plan $plan -DryRun:$dryRun
Write-Output $summary
