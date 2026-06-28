#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates a GitHub Actions build matrix (JSON) from a declarative config.

.DESCRIPTION
    Reads a matrix configuration (from -ConfigPath, -ConfigJson, or the
    MATRIX_CONFIG_PATH environment variable), expands it via the MatrixGenerator
    module (cartesian product + exclude + include), validates the result against
    the configured max-size, and prints the matrix between machine-readable
    markers:

        ===MATRIX-JSON-START===
        { ...full result object (pretty)... }
        ===MATRIX-JSON-END===
        matrix-count=<n>
        matrix-max-parallel=<n|null>
        matrix-fail-fast=<true|false>
        matrix-max-size=<n>

    When running inside GitHub Actions (i.e. $GITHUB_OUTPUT is set) it also
    publishes step outputs: `matrix` (the {include:[...]} object, ready for
    fromJSON), `json` (the full object), and the scalars `count`,
    `max-parallel`, `fail-fast`.

.PARAMETER ConfigPath
    Path to a JSON config file. Defaults to $MATRIX_CONFIG_PATH or
    'matrix-config.json' when neither -ConfigPath nor -ConfigJson is given.

.PARAMETER ConfigJson
    Inline JSON config string (alternative to -ConfigPath).

.PARAMETER OutFile
    Optional path to also write the full matrix JSON to.

.EXAMPLE
    ./Generate-Matrix.ps1 -ConfigPath fixtures/basic.json
#>
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $ConfigJson,
    [string] $OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the generator module relative to this script so it works from any CWD.
$modulePath = Join-Path $PSScriptRoot 'src' 'MatrixGenerator.psm1'
Import-Module $modulePath -Force

function Write-StepOutput {
    <#
    .SYNOPSIS
        Appends a GitHub Actions step output to $GITHUB_OUTPUT (no-op locally).
    .DESCRIPTION
        Scalars use the `name=value` form; multiline/structured values use the
        delimiter (heredoc) form GitHub requires for anything that might contain
        special characters.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value,
        [switch] $Multiline
    )
    if ([string]::IsNullOrEmpty($env:GITHUB_OUTPUT)) { return }

    if ($Multiline) {
        $delim = "ghadelim_$([guid]::NewGuid().ToString('N'))"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name<<$delim"
        Add-Content -Path $env:GITHUB_OUTPUT -Value $Value
        Add-Content -Path $env:GITHUB_OUTPUT -Value $delim
    }
    else {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
}

try {
    # --- Resolve the configuration source -------------------------------------
    if ($ConfigJson) {
        $rawJson = $ConfigJson
        $source  = '<inline>'
    }
    else {
        if (-not $ConfigPath) {
            $ConfigPath = if ($env:MATRIX_CONFIG_PATH) { $env:MATRIX_CONFIG_PATH } else { 'matrix-config.json' }
        }
        if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
            throw "Config file not found: '$ConfigPath'. Provide -ConfigPath, -ConfigJson, or set MATRIX_CONFIG_PATH."
        }
        $rawJson = Get-Content -Path $ConfigPath -Raw
        $source  = $ConfigPath
    }

    # --- Parse JSON (friendly error) ------------------------------------------
    try {
        $config = $rawJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse JSON config from '$source': $($_.Exception.Message)"
    }

    # --- Generate + serialise -------------------------------------------------
    $result      = New-BuildMatrix -Config $config
    $fullJson    = $result        | ConvertTo-Json -Depth 16
    $matrixJson  = $result.matrix | ConvertTo-Json -Depth 16 -Compress
    $fullCompact = $result        | ConvertTo-Json -Depth 16 -Compress

    $maxParallelDisplay = if ($null -eq $result.'max-parallel') { 'null' } else { "$($result.'max-parallel')" }
    $failFastDisplay    = "$($result.'fail-fast')".ToLowerInvariant()

    # --- Machine/human-readable stdout (captured by act + the test harness) ---
    Write-Output '===MATRIX-JSON-START==='
    Write-Output $fullJson
    Write-Output '===MATRIX-JSON-END==='
    Write-Output "matrix-count=$($result.count)"
    Write-Output "matrix-max-parallel=$maxParallelDisplay"
    Write-Output "matrix-fail-fast=$failFastDisplay"
    Write-Output "matrix-max-size=$($result.'max-size')"

    # --- GitHub Actions step outputs ------------------------------------------
    # NB: output names are camelCase (not kebab-case) because GitHub Actions
    # expressions parse '-' as subtraction, so `steps.x.outputs.max-parallel`
    # would be invalid; `steps.x.outputs.maxParallel` is safe.
    Write-StepOutput -Name 'matrix'      -Value $matrixJson  -Multiline
    Write-StepOutput -Name 'json'        -Value $fullCompact -Multiline
    Write-StepOutput -Name 'count'       -Value "$($result.count)"
    Write-StepOutput -Name 'maxParallel' -Value $maxParallelDisplay
    Write-StepOutput -Name 'failFast'    -Value $failFastDisplay

    if ($OutFile) {
        Set-Content -Path $OutFile -Value $fullJson -Encoding utf8
    }

    exit 0
}
catch {
    $msg = $_.Exception.Message
    # GitHub-friendly annotation on stdout + plain message on stderr so both the
    # Actions UI and the test harness can surface the failure.
    Write-Output "::error::$msg"
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}
