<#
.SYNOPSIS
    CLI entry point: applies artifact retention policies from a JSON config
    and prints a deletion plan plus summary.

.DESCRIPTION
    The config file bundles the mock artifact inventory with the retention
    policy and a fixed reference date so runs are fully deterministic:

        {
          "referenceDate": "2026-07-01T00:00:00Z",
          "policy": {
            "maxAgeDays": 30,
            "maxTotalSizeMB": 400,
            "keepLatestPerWorkflow": 1,
            "dryRun": true
          },
          "artifacts": [
            { "name": "...", "sizeBytes": 1, "createdAt": "...", "workflowRunId": 1 }
          ]
        }

    Output is line-oriented and stable on purpose — the CI harness parses it
    and asserts exact values (counts, reclaimed MB, per-artifact actions).

.EXAMPLE
    ./Invoke-ArtifactCleanup.ps1 -ConfigPath fixtures/case1.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force

# --- Load and validate the config -----------------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: '$ConfigPath'. Provide a JSON file with 'referenceDate', 'policy' and 'artifacts'."
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    throw "Config file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
}

foreach ($key in 'referenceDate', 'policy', 'artifacts') {
    if (-not ($config.PSObject.Properties.Name -contains $key)) {
        throw "Config file '$ConfigPath' is missing the required '$key' key."
    }
}

# Normalize the JSON records into the property names the module expects.
$artifacts = @(
    foreach ($a in $config.artifacts) {
        [pscustomobject]@{
            Name          = $a.name
            SizeBytes     = [long]$a.sizeBytes
            CreatedAt     = [string]$a.createdAt
            WorkflowRunId = $a.workflowRunId
        }
    }
)

$policy = $config.policy
$dryRun = [bool]$policy.dryRun

# --- Build the plan --------------------------------------------------------
$plan = Get-ArtifactRetentionPlan `
    -Artifacts $artifacts `
    -MaxAgeDays ([int]$policy.maxAgeDays) `
    -KeepLatestPerWorkflow ([int]$policy.keepLatestPerWorkflow) `
    -MaxTotalSizeBytes ([long]$policy.maxTotalSizeMB * 1MB) `
    -ReferenceDate ([datetime]::Parse($config.referenceDate).ToUniversalTime())

function Format-Mb([long]$Bytes) {
    # Whole megabytes render without decimals ("410 MB"); fractional sizes
    # keep two decimals so nothing is silently rounded away.
    $mb = $Bytes / 1MB
    if ($mb -eq [math]::Truncate($mb)) { '{0} MB' -f [long]$mb } else { '{0:0.00} MB' -f $mb }
}

# --- Report the plan --------------------------------------------------------
Write-Output '=== Artifact Cleanup Plan ==='
Write-Output ("Mode: {0}" -f ($dryRun ? 'DRY RUN' : 'EXECUTE'))

foreach ($item in $plan.Delete) {
    Write-Output ("DELETE {0} (run {1}, {2}, {3})" -f $item.Name, $item.WorkflowRunId, (Format-Mb $item.SizeBytes), $item.Reason)
}
foreach ($item in $plan.Retain) {
    Write-Output ("RETAIN {0} (run {1}, {2})" -f $item.Name, $item.WorkflowRunId, (Format-Mb $item.SizeBytes))
}

# --- Execute (mock deleter — this tool works on mock metadata) --------------
$result = Invoke-ArtifactCleanup -Plan $plan -DryRun:$dryRun

# Only an executed run reports actual deletions; a dry run only plans them.
if (-not $result.DryRun) {
    foreach ($name in $result.DeletedNames) {
        Write-Output ("Deleted artifact: {0}" -f $name)
    }
}

# --- Summary ----------------------------------------------------------------
Write-Output '=== Summary ==='
Write-Output ("Artifacts retained: {0}" -f $plan.Summary.RetainedCount)
Write-Output ("Artifacts deleted: {0}" -f $plan.Summary.DeletedCount)
Write-Output ("Space reclaimed: {0}" -f (Format-Mb $plan.Summary.ReclaimedBytes))
Write-Output ("Retained size: {0}" -f (Format-Mb $plan.Summary.RetainedBytes))
