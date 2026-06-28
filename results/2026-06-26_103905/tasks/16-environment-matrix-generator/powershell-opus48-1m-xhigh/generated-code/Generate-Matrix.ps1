#!/usr/bin/env pwsh
#
# Generate-Matrix.ps1
#
# Thin CLI wrapper around MatrixGenerator.psm1. Reads a JSON configuration file,
# resolves the GitHub Actions build matrix, and:
#   * prints a human-readable summary plus machine-parseable, delimited lines
#     (MATRIX_SIZE / MAX_PARALLEL / FAIL_FAST / MATRIX_JSON) to stdout, and
#   * when running inside GitHub Actions (or act), writes step outputs to
#     $GITHUB_OUTPUT so a downstream job can consume the matrix via fromJson().
#
# Usage:
#   ./Generate-Matrix.ps1 -ConfigPath matrix-config.json
#   MATRIX_CONFIG_PATH=fixtures/basic.json ./Generate-Matrix.ps1
#
[CmdletBinding()]
param(
    # Path to the matrix configuration JSON. Falls back to the MATRIX_CONFIG_PATH
    # environment variable, then to "matrix-config.json" in the current directory.
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve the module next to this script so the CLI works from any CWD.
$moduleFile = Join-Path $PSScriptRoot 'MatrixGenerator.psm1'
Import-Module $moduleFile -Force

try {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = if ($env:MATRIX_CONFIG_PATH) { $env:MATRIX_CONFIG_PATH } else { 'matrix-config.json' }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Matrix configuration file not found: '$ConfigPath'. Set -ConfigPath or the MATRIX_CONFIG_PATH environment variable."
    }

    Write-Host "Reading matrix configuration from: $ConfigPath"
    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Matrix configuration file '$ConfigPath' is empty."
    }

    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        throw "Matrix configuration file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    # Resolve the matrix (this throws on invalid config / oversize matrices).
    $result = New-BuildMatrix -Config $config

    $matrixJson  = $result.matrix | ConvertTo-Json -Depth 12 -Compress
    $maxParallel = if ($null -ne $result.'max-parallel') { $result.'max-parallel' } else { '' }
    $failFast    = ($result.'fail-fast').ToString().ToLowerInvariant()

    # --- Human readable summary -------------------------------------------------
    Write-Host ''
    Write-Host '===== Resolved build matrix ====='
    Write-Host ($result.matrix | ConvertTo-Json -Depth 12)
    Write-Host '================================='
    Write-Host ''

    # --- Machine parseable, stable delimited lines ------------------------------
    # The act test harness greps for exactly these keys.
    Write-Host '----- matrix-generator output -----'
    Write-Host "MATRIX_SIZE=$($result.size)"
    Write-Host "MAX_PARALLEL=$maxParallel"
    Write-Host "FAIL_FAST=$failFast"
    Write-Host "MATRIX_JSON=$matrixJson"
    Write-Host '----- end matrix-generator output -----'

    # --- GitHub Actions step outputs (for the downstream dynamic matrix job) ----
    # Output names use underscores: '-' would be parsed as subtraction in
    # ${{ steps.*.outputs.* }} expressions.
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "matrix=$matrixJson"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "size=$($result.size)"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "max_parallel=$maxParallel"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "fail_fast=$failFast"
        Write-Host "Wrote step outputs to GITHUB_OUTPUT."
    }

    exit 0
}
catch {
    # Surface a clear, actionable error and fail the step.
    Write-Host "::error::Matrix generation failed: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
