#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Convenience entry point for the act-based CI integration harness.

.DESCRIPTION
    Runs tests/ActIntegration.Tests.ps1, which drives the GitHub Actions workflow
    through `act` once per test-case fixture, writes the aggregate output to
    act-result.txt, and asserts on the exact expected values.

    This is just a thin wrapper around Invoke-Pester so there is one obvious
    command to run the (slow) integration suite. It exits non-zero if any case
    fails, so it can be used as a CI gate.

    Each test case is one `act push` - expect this to take ~1 minute per case.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$testFile = Join-Path $PSScriptRoot 'tests/ActIntegration.Tests.ps1'

$config = New-PesterConfiguration
$config.Run.Path = $testFile
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $config

Write-Output ""
Write-Output ("act integration: {0} passed, {1} failed" -f $result.PassedCount, $result.FailedCount)
Write-Output ("act-result.txt: " + (Join-Path $PSScriptRoot 'act-result.txt'))

exit ([int]($result.FailedCount -gt 0))
