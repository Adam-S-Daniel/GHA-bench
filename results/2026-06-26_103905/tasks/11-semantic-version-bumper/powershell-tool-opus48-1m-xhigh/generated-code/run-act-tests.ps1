#!/usr/bin/env pwsh
#
# run-act-tests.ps1 — convenience entry point for the act-based integration
# harness. It simply runs tests/Act.Integration.Tests.ps1, which spins up a
# throwaway git repo per test case, executes the real workflow with
# `act push --rm`, writes the delimited output to act-result.txt, and asserts
# the exact expected version for each case.
#
# Usage:  ./run-act-tests.ps1
#
# Requires: act + Docker on the host, and the act-ubuntu-pwsh:latest image
# referenced by .actrc.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $here 'tests/Act.Integration.Tests.ps1'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Write-Host "Running act integration harness (one 'act push' per test case)..."
Invoke-Pester -Configuration $config
