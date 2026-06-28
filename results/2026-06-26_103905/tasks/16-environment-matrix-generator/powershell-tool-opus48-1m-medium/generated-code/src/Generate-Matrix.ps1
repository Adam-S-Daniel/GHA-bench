#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the build-matrix generator.

.DESCRIPTION
    Loads a JSON configuration file, generates the GitHub Actions strategy
    matrix, validates it against the configured max-size, and writes the
    resulting JSON to stdout. Exits non-zero with a meaningful message on error.

.PARAMETER ConfigPath
    Path to the JSON configuration file.

.EXAMPLE
    ./Generate-Matrix.ps1 -ConfigPath fixtures/basic.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the matrix logic module that lives next to this script.
Import-Module (Join-Path $PSScriptRoot 'BuildMatrix.psm1') -Force

try {
    $json = Invoke-MatrixGenerator -ConfigPath $ConfigPath
    Write-Output $json
}
catch {
    # Surface a clear error message and a non-zero exit code for CI.
    Write-Error "Matrix generation failed: $($_.Exception.Message)"
    exit 1
}
