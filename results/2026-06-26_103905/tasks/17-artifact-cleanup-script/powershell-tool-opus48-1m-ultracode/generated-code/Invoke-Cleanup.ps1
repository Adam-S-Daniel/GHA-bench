#Requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point: load a cleanup fixture/config, apply retention policies and
    print a deterministic deletion plan + summary.

.DESCRIPTION
    This is the thin command-line wrapper the GitHub Actions workflow runs. It
    composes the pure functions in ArtifactCleanup.psm1:

        Import-CleanupConfig  -> Invoke-ArtifactCleanup  -> Format-CleanupReport

    All policy thresholds, the reference date and the dry-run flag come from the
    self-contained JSON config so a single file fully determines the output —
    which is exactly what the act test harness varies per test case.

    Dry-run is the default (driven by the config's "dryRun", which itself
    defaults to true). In live mode the supplied delete action would call the
    real artifact-deletion API; here the artifacts are mock data so it just logs.

.PARAMETER FixturePath
    Path to the JSON config. Falls back to the FIXTURE_PATH env var, then to
    'fixtures/artifacts.json' relative to this script.

.OUTPUTS
    Writes the formatted plan to stdout. Exit code 0 on success, 1 on any error.
#>
[CmdletBinding()]
param(
    [string] $FixturePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Resolve paths relative to this script so the workflow can invoke it from
    # any working directory.
    $here = $PSScriptRoot
    Import-Module (Join-Path $here 'ArtifactCleanup.psm1') -Force

    # Precedence: explicit param > FIXTURE_PATH env var > repo default.
    if ([string]::IsNullOrWhiteSpace($FixturePath)) {
        $FixturePath = if (-not [string]::IsNullOrWhiteSpace($env:FIXTURE_PATH)) {
            $env:FIXTURE_PATH
        } else {
            Join-Path $here 'fixtures/artifacts.json'
        }
    }

    Write-Host "Loading cleanup config from: $FixturePath"
    $config = Import-CleanupConfig -Path $FixturePath

    # Reference "now" for age policies: prefer the config's fixed date (keeps CI
    # output deterministic), otherwise use the real current UTC time.
    $now = if ($null -ne $config.ReferenceDate) { $config.ReferenceDate } else { (Get-Date).ToUniversalTime() }

    # Build the argument splat from only the policies present in the config.
    $invokeArgs = @{
        Artifact = $config.Artifacts
        Now      = $now
    }
    foreach ($k in $config.Policies.Keys) { $invokeArgs[$k] = $config.Policies[$k] }
    if ($config.DryRun) { $invokeArgs['DryRun'] = $true }

    # In live mode, this is where a real run would call the GitHub REST API to
    # delete each artifact. With mock data we simply record the action.
    $deleteAction = { param($a) Write-Host "  [delete] $($a.Name) ($($a.SizeBytes) bytes)" }
    if (-not $config.DryRun) { $invokeArgs['DeleteAction'] = $deleteAction }

    $plan = Invoke-ArtifactCleanup @invokeArgs

    # Emit the deterministic report for downstream parsing / job summaries.
    $report = Format-CleanupReport -Plan $plan
    Write-Output $report

    # Also publish the summary to the GitHub Actions job summary when available.
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        @(
            '## Artifact Cleanup Summary',
            '',
            "- Mode: **$(if ($plan.DryRun) { 'DRY-RUN' } else { 'LIVE' })**",
            "- Total artifacts: $($plan.Summary.TotalArtifacts)",
            "- Deleted: $($plan.Summary.DeletedCount)",
            "- Retained: $($plan.Summary.RetainedCount)",
            "- Space reclaimed: $($plan.Summary.SpaceReclaimedBytes) bytes"
        ) -join [Environment]::NewLine | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    }

    exit 0
}
catch {
    # Surface a single, clear error line and fail the step.
    Write-Error "artifact-cleanup failed: $($_.Exception.Message)"
    exit 1
}
