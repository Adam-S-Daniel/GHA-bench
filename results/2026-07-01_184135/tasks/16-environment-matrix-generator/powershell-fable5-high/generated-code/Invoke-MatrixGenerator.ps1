<#
.SYNOPSIS
    CLI entry point for the Environment Matrix Generator.

.DESCRIPTION
    Reads a JSON configuration describing OS options, language versions, and
    feature flags (plus include/exclude rules, max-parallel, fail-fast, and a
    maximum matrix size), and prints the complete GitHub Actions strategy
    JSON (compressed, single line) to stdout.

    Exit codes: 0 on success, 1 on any error (missing file, malformed JSON,
    invalid configuration, oversize matrix) with a meaningful message on
    stderr.

.PARAMETER ConfigPath
    Path to the JSON configuration file.

.PARAMETER OutputPath
    Optional path; when set, the JSON is also written to this file.

.EXAMPLE
    ./Invoke-MatrixGenerator.ps1 -ConfigPath fixtures/ci-config.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src' 'MatrixGenerator.ps1')

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: '$ConfigPath'."
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Configuration file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }

    $strategy = New-BuildMatrixStrategy -Config $config
    # -Compress keeps the matrix on one line so it can flow straight into a
    # $GITHUB_OUTPUT variable and ${{ fromJSON(...) }}.
    $json = ConvertTo-Json -InputObject $strategy -Depth 10 -Compress

    if ($OutputPath) {
        Set-Content -LiteralPath $OutputPath -Value $json -NoNewline
    }
    Write-Output $json
    exit 0
}
catch {
    Write-Error "Matrix generation failed: $($_.Exception.Message)"
    exit 1
}
