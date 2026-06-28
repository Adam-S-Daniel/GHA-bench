#requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point: reads a matrix config (JSON) and prints the generated
    GitHub Actions build matrix as JSON.

.DESCRIPTION
    Reads configuration from a file (-ConfigPath), an inline string (-ConfigJson),
    or stdin (when neither is given) and emits the expanded strategy matrix.

    The emitted JSON has GitHub-style keys:
        fail-fast, max-parallel, matrix, job-count, jobs

    On any validation or parse error it writes a meaningful message to stderr
    and exits with a non-zero status, so it composes cleanly in CI.

.PARAMETER ConfigPath
    Path to a JSON config file.

.PARAMETER ConfigJson
    Inline JSON config string (takes precedence over stdin, not over ConfigPath).

.EXAMPLE
    pwsh ./New-BuildMatrix.ps1 -ConfigPath ./fixtures/basic.json

.EXAMPLE
    Get-Content cfg.json -Raw | pwsh ./New-BuildMatrix.ps1
#>
[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $ConfigJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the implementation module that lives next to this script.
Import-Module (Join-Path $PSScriptRoot 'BuildMatrix.psm1') -Force

try {
    # Resolve the raw JSON from the chosen source.
    if ($ConfigPath) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $json = Get-Content -LiteralPath $ConfigPath -Raw
    }
    elseif ($ConfigJson) {
        $json = $ConfigJson
    }
    else {
        # Fall back to stdin so the script is pipe-friendly.
        $json = [Console]::In.ReadToEnd()
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        throw 'No configuration provided. Supply -ConfigPath, -ConfigJson, or pipe JSON via stdin.'
    }

    $config = ConvertFrom-MatrixConfigJson -Json $json
    $matrix = New-BuildMatrix -Config $config

    # Print the full matrix JSON to stdout.
    $matrix | ConvertTo-MatrixJson
    exit 0
}
catch {
    # Graceful failure: meaningful message on stderr, non-zero exit code.
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
