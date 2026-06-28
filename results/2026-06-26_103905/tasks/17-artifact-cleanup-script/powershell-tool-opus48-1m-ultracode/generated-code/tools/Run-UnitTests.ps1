#Requires -Version 7.0
<#
.SYNOPSIS
    Run the hermetic Pester unit suite (Tag 'Unit') and fail on any failure.

.DESCRIPTION
    Invoked by the CI workflow's `test` job. It deliberately targets ONLY the
    pure unit-test file and the 'Unit' tag so it never tries to run the
    workflow-structure tests (need actionlint) or the act-acceptance tests (need
    Docker) inside the container — those run on the host.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
Import-Module Pester -MinimumVersion 5.0.0

$config = New-PesterConfiguration
$config.Run.Path        = Join-Path $repoRoot 'tests/ArtifactCleanup.Tests.ps1'
$config.Filter.Tag      = 'Unit'
$config.Output.Verbosity = 'Detailed'
$config.Run.PassThru    = $true

$result = Invoke-Pester -Configuration $config

Write-Host "Pester results: Passed=$($result.PassedCount) Failed=$($result.FailedCount) Skipped=$($result.SkippedCount)"
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) unit test(s) failed."
}
Write-Host 'All unit tests passed.'
