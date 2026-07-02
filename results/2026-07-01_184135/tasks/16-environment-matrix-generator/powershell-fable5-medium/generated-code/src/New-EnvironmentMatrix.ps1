<#
.SYNOPSIS
    CLI entry point: reads a matrix configuration JSON file and prints the
    generated GitHub Actions strategy matrix as compact JSON on stdout.
.DESCRIPTION
    Exit codes: 0 on success, 1 on any error (missing file, invalid JSON,
    invalid configuration, matrix too large). Errors are written to stderr
    with a meaningful message so CI logs show the root cause.
.EXAMPLE
    ./New-EnvironmentMatrix.ps1 -ConfigPath fixtures/basic.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'MatrixGenerator.psm1') -Force

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    try {
        $config = $raw | ConvertFrom-Json
    }
    catch {
        throw "Config file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    $matrix = New-BuildMatrix -Config $config
    ConvertTo-MatrixJson -Matrix $matrix
    exit 0
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
