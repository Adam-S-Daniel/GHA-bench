#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Command-line entry point for the artifact retention cleanup tool.

.DESCRIPTION
    Loads a self-contained "scenario" JSON file (policy + mode + artifact
    metadata -- see Import-CleanupScenario), evaluates the retention policies,
    and prints a deletion plan plus summary. Designed to be invoked from a
    GitHub Actions workflow with `shell: pwsh`.

    Input is taken from -ScenarioPath or, if omitted, the CLEANUP_SCENARIO_PATH
    environment variable. The -DryRun / -Execute switches override the scenario's
    own dryRun setting (dry-run wins if both are somehow supplied).

.EXAMPLE
    ./Invoke-ArtifactCleanupCli.ps1 -ScenarioPath fixtures/scenario.json

.EXAMPLE
    CLEANUP_SCENARIO_PATH=fixtures/scenario.json ./Invoke-ArtifactCleanupCli.ps1 -Execute
#>
[CmdletBinding()]
param(
    # Path to the scenario JSON file. Falls back to the CLEANUP_SCENARIO_PATH env var.
    [string]$ScenarioPath = $env:CLEANUP_SCENARIO_PATH,

    # Force dry-run mode regardless of the scenario file.
    [switch]$DryRun,

    # Force execute mode regardless of the scenario file.
    [switch]$Execute
)

# Fail fast on any unhandled error so the workflow step reports failure.
$ErrorActionPreference = 'Stop'

try {
    if ([string]::IsNullOrWhiteSpace($ScenarioPath)) {
        throw "No scenario path provided. Pass -ScenarioPath <file> or set CLEANUP_SCENARIO_PATH."
    }

    # Import the implementation module that sits next to this script.
    $modulePath = Join-Path $PSScriptRoot 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force

    $scenario = Import-CleanupScenario -Path $ScenarioPath

    # Resolve the effective run mode: scenario default, then CLI overrides.
    $dryRunEffective = $scenario.DryRun
    if ($Execute) { $dryRunEffective = $false }
    if ($DryRun)  { $dryRunEffective = $true }

    # Forward only the policies that the scenario actually enabled.
    $invokeArgs = @{
        Artifacts     = $scenario.Artifacts
        ReferenceDate = $scenario.ReferenceDate
    }
    if ($null -ne $scenario.Policy.MaxAgeDays)            { $invokeArgs.MaxAgeDays            = $scenario.Policy.MaxAgeDays }
    if ($null -ne $scenario.Policy.MaxTotalSizeBytes)     { $invokeArgs.MaxTotalSizeBytes     = $scenario.Policy.MaxTotalSizeBytes }
    if ($null -ne $scenario.Policy.KeepLatestPerWorkflow) { $invokeArgs.KeepLatestPerWorkflow = $scenario.Policy.KeepLatestPerWorkflow }
    if ($dryRunEffective) { $invokeArgs.DryRun = $true }

    $plan = Invoke-ArtifactCleanup @invokeArgs

    # Emit the report between explicit markers so automation can extract it
    # reliably from surrounding CI log noise.
    Write-Output '##CLEANUP-REPORT-BEGIN##'
    Write-Output (Format-CleanupReport -Plan $plan)
    Write-Output '##CLEANUP-REPORT-END##'

    exit 0
}
catch {
    # Relax the error preference so Write-Error reports on the error stream
    # without re-throwing (which would bypass our explicit exit code), then fail
    # the step deterministically with a non-zero exit.
    $ErrorActionPreference = 'Continue'
    Write-Error "artifact-cleanup failed: $($_.Exception.Message)"
    exit 1
}
