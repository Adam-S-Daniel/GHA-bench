<#
.SYNOPSIS
    CLI entry point: reads a matrix config JSON file and prints the generated
    GitHub Actions strategy (fail-fast/max-parallel/matrix) as JSON.
.DESCRIPTION
    Thin wrapper around EnvironmentMatrixGenerator.psm1 for use from a
    workflow `run:` step. On success, prints the JSON and returns normally
    (no explicit `exit 0`, so callers that dot/call this script in-process
    can keep executing afterwards). On failure, prints a meaningful error to
    stderr and calls `exit 1` - invoke this script as a separate `pwsh`
    process (not via `&`/dot-sourcing) if the caller needs to observe that
    exit code without also terminating itself.
.PARAMETER ConfigPath
    Path to the JSON matrix configuration file.
.PARAMETER Compress
    Emit compact single-line JSON instead of pretty-printed JSON.
.PARAMETER Depth
    ConvertTo-Json depth (default 10, generous for nested include entries).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [switch]$Compress,

    [int]$Depth = 10
)

Import-Module (Join-Path $PSScriptRoot 'EnvironmentMatrixGenerator.psm1') -Force

try {
    $config = Get-MatrixConfig -Path $ConfigPath
    $json = ConvertTo-MatrixJson -Config $config -Depth $Depth -Compress:$Compress
}
catch {
    Write-Error "Environment matrix generation failed: $($_.Exception.Message)"
    exit 1
}

Write-Output $json
