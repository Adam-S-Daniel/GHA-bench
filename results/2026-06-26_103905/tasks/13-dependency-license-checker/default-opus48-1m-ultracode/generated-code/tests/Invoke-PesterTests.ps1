#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run the Pester unit test suite. Used by the GitHub Actions workflow so that
    ALL tests execute inside the CI pipeline (via act).
.DESCRIPTION
    Configures Pester 5 to run the module test file and to exit with a non-zero
    code if any test fails, which fails the workflow job.
#>
$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path        = (Join-Path $PSScriptRoot 'DependencyLicenseChecker.Tests.ps1')
$config.Run.Exit        = $true          # non-zero exit on failure -> fail the job
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
