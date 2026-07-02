#Requires -Version 7.0
<#
.SYNOPSIS
    Generates a GitHub Actions build matrix (as JSON) from a configuration
    describing OS options, language versions, and feature flags.

.DESCRIPTION
    Reads a JSON configuration file describing one or more matrix dimensions
    (e.g. os, version, flags), applies include/exclude rules the same way
    GitHub Actions' strategy.matrix does, validates the resulting matrix does
    not exceed a maximum size, and prints the complete matrix as JSON in the
    shape `{ "strategy": { "fail-fast": ..., "max-parallel": ..., "matrix": { "include": [...] } } }`.

.PARAMETER ConfigPath
    Path to the JSON configuration file.

.PARAMETER OutputPath
    Optional path to also write the resulting JSON to.

.PARAMETER MaxMatrixSize
    Optional override for the maximum allowed number of matrix combinations.
    A value in the config file's own "maxMatrixSize" key always takes
    precedence over this parameter.

.EXAMPLE
    ./EnvironmentMatrixGenerator.ps1 -ConfigPath ./fixtures/basic-config.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$ConfigPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [Nullable[int]]$MaxMatrixSize
)

. (Join-Path $PSScriptRoot 'MatrixFunctions.ps1')

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Configuration file not found: $ConfigPath"
}

try {
    $rawJson = Get-Content -Path $ConfigPath -Raw
    $config = $rawJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Failed to parse configuration JSON at '$ConfigPath': $($_.Exception.Message)"
}

$matrix = New-BuildMatrix -Config $config -MaxMatrixSizeOverride $MaxMatrixSize
$json = $matrix | ConvertTo-Json -Depth 20 -Compress

Write-Output $json

if ($OutputPath) {
    Set-Content -Path $OutputPath -Value $json
}

if ($env:GITHUB_OUTPUT) {
    "matrix=$json" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
