<#
    Invoke-MatrixGenerator.ps1
    --------------------------
    Thin command-line wrapper around the BuildMatrix module. Reads a configuration
    file, builds the validated GitHub Actions strategy, prints the matrix JSON
    (delimited so it is easy to pull out of noisy CI logs), and -- when asked --
    publishes the bare strategy.matrix object to $GITHUB_OUTPUT so a downstream job
    can consume it with:

        strategy:
          matrix: ${{ fromJSON(needs.<job>.outputs.matrix) }}

    On any validation error it emits a GitHub `::error::` annotation and exits 1.
#>
[CmdletBinding()]
param(
    # Path to the matrix configuration JSON file.
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    # Optional override for the maximum allowed matrix size.
    [int]$MaxSize,

    # Optional path to also write the full (pretty) matrix JSON to.
    [string]$OutFile,

    # When set, append `matrix=`/`size=` to $GITHUB_OUTPUT for downstream jobs.
    [switch]$GitHubOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the pure logic module that lives next to this script.
Import-Module (Join-Path $PSScriptRoot 'BuildMatrix.psm1') -Force

$depth = 12

try {
    $config = Import-MatrixConfig -Path $ConfigPath

    $params = @{ Config = $config }
    if ($PSBoundParameters.ContainsKey('MaxSize')) { $params['MaxSize'] = $MaxSize }

    $result = Get-BuildMatrix @params
}
catch {
    # Surface a clean, single-line error as a GitHub Actions annotation.
    $message = ($_.Exception.Message -replace '\r?\n', ' ')
    Write-Output "::error::$message"
    exit 1
}

# Human/CI readable output, fenced with markers for reliable extraction.
$pretty = $result | ConvertTo-Json -Depth $depth
Write-Output '===MATRIX-JSON-BEGIN==='
Write-Output $pretty
Write-Output '===MATRIX-JSON-END==='
Write-Output "MATRIX-SIZE:$($result.size)"

if ($OutFile) {
    Set-Content -LiteralPath $OutFile -Value $pretty -Encoding utf8
    Write-Output "Wrote matrix JSON to $OutFile"
}

if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
    # Publish the directly-usable strategy.matrix object (compact, single line).
    $matrixCompact = $result.strategy.matrix | ConvertTo-Json -Depth $depth -Compress
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "matrix=$matrixCompact"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "size=$($result.size)"
}

exit 0
