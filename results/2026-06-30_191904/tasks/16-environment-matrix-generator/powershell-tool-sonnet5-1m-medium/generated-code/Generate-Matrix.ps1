<#
    .SYNOPSIS
    CLI entry point: reads a JSON environment-matrix config file, builds the
    GitHub Actions strategy matrix, prints it as compact JSON, and (when run
    inside a GitHub Actions job) writes it to $env:GITHUB_OUTPUT as `matrix`.

    .PARAMETER ConfigPath
    Path to the JSON config describing matrix axes, include/exclude rules,
    max-parallel and fail-fast settings.
#>
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MatrixGenerator.psm1') -Force

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Config file not found at path: $ConfigPath"
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$matrix = New-BuildMatrix -Config $config

$json = $matrix | ConvertTo-Json -Depth 10 -Compress

Write-Output "Generated matrix with $($matrix.matrix.include.Count) combination(s) from '$ConfigPath'."
Write-Output $json

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "matrix=$json"
}
