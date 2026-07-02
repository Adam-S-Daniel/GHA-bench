<#
.SYNOPSIS
    CI wrapper: runs the artifact cleanup with parameters from a JSON file.
.DESCRIPTION
    Reads a params file (default ci/params.json, overridable via the
    CLEANUP_PARAMS environment variable) describing which fixture to use and
    which retention policies to apply, then invokes Invoke-ArtifactCleanup.ps1.
    This keeps the workflow YAML trivial and lets the act test harness swap
    the params file per test case.
#>
[CmdletBinding()]
param(
    [string]$ParamsPath = $(if ($env:CLEANUP_PARAMS) { $env:CLEANUP_PARAMS } else { 'ci/params.json' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

if (-not (Test-Path -LiteralPath $ParamsPath)) {
    throw "Cleanup params file not found: '$ParamsPath'."
}
try {
    $params = Get-Content -LiteralPath $ParamsPath -Raw | ConvertFrom-Json
}
catch {
    throw "Cleanup params file '$ParamsPath' is not valid JSON: $($_.Exception.Message)"
}

Write-Output "Using cleanup params from $ParamsPath"

# Only forward the policies the params file actually sets.
$cliArgs = @{ ArtifactsPath = (Join-Path $repoRoot $params.ArtifactsPath) }
foreach ($name in 'MaxAgeDays', 'KeepLatestPerWorkflow', 'MaxTotalSizeBytes', 'ReferenceDate') {
    $prop = $params.PSObject.Properties[$name]
    if ($prop -and $null -ne $prop.Value) { $cliArgs[$name] = $prop.Value }
}
if ($params.PSObject.Properties['DryRun'] -and $params.DryRun) { $cliArgs.DryRun = $true }

& (Join-Path $repoRoot 'Invoke-ArtifactCleanup.ps1') @cliArgs
