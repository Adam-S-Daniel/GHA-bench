#requires -Version 7.0
<#
    RunTests.ps1

    Convenience wrapper around Invoke-Pester.

    By default it runs the fast tests (unit + workflow structure). Pass
    -IncludeAct to also run the end-to-end act harness (requires Docker + act),
    which performs real `act push` runs and (re)writes act-result.txt.
#>
[CmdletBinding()]
param(
    # Also run tests/ActHarness.Tests.ps1 (drives the workflow through act).
    [switch]$IncludeAct
)

$ErrorActionPreference = 'Stop'

$paths = @(
    (Join-Path $PSScriptRoot 'tests/LicenseChecker.Tests.ps1'),
    (Join-Path $PSScriptRoot 'tests/WorkflowStructure.Tests.ps1')
)
if ($IncludeAct) {
    $paths += (Join-Path $PSScriptRoot 'tests/ActHarness.Tests.ps1')
}

$config = New-PesterConfiguration
$config.Run.Path = $paths
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
