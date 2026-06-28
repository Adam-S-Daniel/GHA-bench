#!/usr/bin/env pwsh
#
# Generate-Matrix.ps1
#
# CLI entry point for the build-matrix generator. Reads a strategy-style JSON
# configuration, resolves it into a concrete GitHub Actions matrix, and emits:
#
#   * a human-readable, delimited pretty-printed strategy block on stdout,
#   * a single-line `STRATEGY_JSON=<compact json>` for easy machine parsing,
#   * GitHub Actions step outputs (matrix / fail-fast / max-parallel) when
#     $env:GITHUB_OUTPUT is present, so a downstream job can consume the matrix
#     dynamically via `${{ fromJSON(needs.<job>.outputs.matrix) }}`.
#
# Exit codes:
#   0  success
#   1  any error (missing file, invalid JSON, validation failure, oversize matrix)
#
# Usage:
#   ./Generate-Matrix.ps1 -ConfigPath ./matrix-config.json
#   MATRIX_CONFIG is honoured as a fallback when -ConfigPath is omitted.

[CmdletBinding()]
param(
    # Path to the JSON configuration file. Falls back to the MATRIX_CONFIG
    # environment variable, then to ./matrix-config.json.
    [string] $ConfigPath
)

# Fail fast on unexpected errors so a typo never produces a half-built matrix.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Resolve the configuration path with sensible fallbacks.
    if (-not $ConfigPath) {
        if ($env:MATRIX_CONFIG) { $ConfigPath = $env:MATRIX_CONFIG }
        else { $ConfigPath = Join-Path (Get-Location) 'matrix-config.json' }
    }

    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: '$ConfigPath'."
    }

    # Import the module living next to this script.
    $modulePath = Join-Path $PSScriptRoot 'BuildMatrix.psm1'
    Import-Module $modulePath -Force

    # Parse the configuration. ConvertFrom-Json gives a PSCustomObject which
    # New-BuildMatrix knows how to normalize.
    $raw = Get-Content -Path $ConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Configuration file '$ConfigPath' is empty."
    }

    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        throw "Configuration file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    # Build the resolved strategy.
    $strategy = New-BuildMatrix -Config $config

    # --- Human-readable output -------------------------------------------------
    $pretty = ConvertTo-StrategyJson -Strategy $strategy
    Write-Output '----- BEGIN STRATEGY -----'
    Write-Output $pretty
    Write-Output '----- END STRATEGY -----'

    # --- Machine-parseable single line ----------------------------------------
    $compact = ConvertTo-StrategyJson -Strategy $strategy -Compress
    Write-Output "STRATEGY_JSON=$compact"

    $combinationCount = @($strategy['matrix'].include).Count
    Write-Output "MATRIX_SIZE=$combinationCount"

    # --- GitHub Actions step outputs ------------------------------------------
    if ($env:GITHUB_OUTPUT) {
        # Emit only the `matrix` object compactly so it can feed fromJSON().
        $matrixCompact = ConvertTo-Json -InputObject $strategy['matrix'] -Depth 20 -Compress
        $lines = @(
            "matrix=$matrixCompact"
            "fail-fast=$($strategy['fail-fast'])"
            "size=$combinationCount"
        )
        if ($strategy.Contains('max-parallel')) {
            $lines += "max-parallel=$($strategy['max-parallel'])"
        }
        $lines | Add-Content -Path $env:GITHUB_OUTPUT -Encoding utf8
    }

    exit 0
}
catch {
    # Surface a clear, single-line error on stderr and fail the step.
    $msg = $_.Exception.Message
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}
