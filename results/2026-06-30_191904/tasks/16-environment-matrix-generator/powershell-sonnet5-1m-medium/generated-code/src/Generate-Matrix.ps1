#Requires -PSEdition Core
<#
    .SYNOPSIS
    CLI entry point: reads a JSON matrix configuration file and prints the
    generated GitHub Actions matrix JSON to stdout (and optionally writes it
    to a GITHUB_OUTPUT-style file for use in a workflow job output).

    .PARAMETER ConfigPath
    Path to a JSON file describing the matrix dimensions and options.

    .PARAMETER GithubOutputPath
    Optional path to a GITHUB_OUTPUT file. When supplied, writes a
    `matrix=<json>` line so a workflow step can expose it as a job output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [string]$GithubOutputPath
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'MatrixGenerator.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

try {
    $configJson = Get-Content -LiteralPath $ConfigPath -Raw
    $config = $configJson | ConvertFrom-Json -AsHashtable -Depth 20
}
catch {
    throw "Failed to parse config file '$ConfigPath' as JSON: $($_.Exception.Message)"
}

$matrixResult = New-EnvironmentMatrix -Config $config
$matrixJson = $matrixResult | ConvertTo-Json -Depth 20 -Compress

Write-Output $matrixJson

if ($GithubOutputPath) {
    $onlyMatrixJson = @{ include = $matrixResult.matrix.include } | ConvertTo-Json -Depth 20 -Compress
    $lines = @("matrix=$onlyMatrixJson")

    if ($matrixResult.Contains('max-parallel')) {
        $lines += "max-parallel=$($matrixResult['max-parallel'])"
    }
    $lines += "fail-fast=$($matrixResult['fail-fast'].ToString().ToLowerInvariant())"

    Add-Content -LiteralPath $GithubOutputPath -Value $lines
}
