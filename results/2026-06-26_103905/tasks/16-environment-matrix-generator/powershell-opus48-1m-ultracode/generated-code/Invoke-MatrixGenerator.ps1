#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generate a GitHub Actions build matrix (strategy JSON) from a configuration file.

.DESCRIPTION
    Thin command-line wrapper around MatrixGenerator.psm1. It reads a JSON
    configuration describing build axes plus optional include/exclude rules,
    fail-fast, max-parallel and max-size, expands it into a fully-resolved
    `strategy.matrix`, validates its size, and writes the complete matrix JSON
    to standard output.

.PARAMETER ConfigPath
    Path to the JSON configuration file.

.PARAMETER OutputPath
    Optional path to also write the strategy JSON to a file.

.PARAMETER GitHubOutput
    When set, appends `matrix`, `strategy` and `count` entries to the file named
    by $env:GITHUB_OUTPUT so downstream jobs can consume them via
    `${{ fromJSON(needs.<job>.outputs.matrix) }}`.

.PARAMETER Summary
    When set, also prints `MATRIX_COUNT[<file>]=N` and
    `MATRIX_INCLUDE[<file>]=<json>` marker lines, which CI assertions can grep.

.PARAMETER Compress
    Emit compact (single-line) JSON instead of indented JSON.

.EXAMPLE
    ./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/basic.config.json

.OUTPUTS
    The complete strategy JSON on standard output. Exit code 0 on success, 1 on
    any handled error (bad config, oversized matrix, ...).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [string]$OutputPath,

    [switch]$GitHubOutput,

    [switch]$Summary,

    [switch]$Compress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the core logic. Resolve relative to this script so it works from any cwd.
Import-Module (Join-Path $PSScriptRoot 'MatrixGenerator.psm1') -Force

try {
    # 1. Load + parse the configuration.
    $config = Read-MatrixConfig -Path $ConfigPath

    # 2. Expand and validate the matrix (throws on oversize / empty / invalid).
    $result = Get-BuildMatrix -Config $config

    # 3. Shape the GitHub Actions strategy + matrix objects.
    $strategy = ConvertTo-StrategyObject -Result $result
    $matrix   = ConvertTo-MatrixObject   -Result $result

    $strategyJson = $strategy | ConvertTo-Json -Depth 10 -Compress:$Compress
    $matrixJson   = $matrix   | ConvertTo-Json -Depth 10 -Compress

    # 4. Optional human/CI-friendly summary markers (tagged with the config name
    #    so multiple invocations in one log can be told apart).
    if ($Summary) {
        $tag = Split-Path -Path $ConfigPath -Leaf
        Write-Output "MATRIX_COUNT[$tag]=$($result.Count)"
        Write-Output "MATRIX_INCLUDE[$tag]=$matrixJson"
    }

    # 5. The complete matrix JSON -- the primary deliverable -- on stdout.
    Write-Output $strategyJson

    # 6. Optional file output.
    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $strategyJson -Encoding utf8
    }

    # 7. Optional GitHub Actions step outputs for downstream jobs.
    if ($GitHubOutput) {
        if ([string]::IsNullOrEmpty($env:GITHUB_OUTPUT)) {
            Write-Warning 'GITHUB_OUTPUT is not set; skipping step-output emission.'
        }
        else {
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "matrix=$matrixJson"
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "strategy=$($strategy | ConvertTo-Json -Depth 10 -Compress)"
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "count=$($result.Count)"
        }
    }

    exit 0
}
catch {
    # Surface a clear, single-line error on stderr and fail the process so CI
    # steps stop on real problems (oversized matrix, malformed config, ...).
    $message = $_.Exception.Message
    $errorId = $_.FullyQualifiedErrorId
    [Console]::Error.WriteLine("ERROR ($errorId): $message")
    exit 1
}
