#requires -Version 7.0
<#
    Invoke-LicenseCheck.ps1

    Command-line entry point for the dependency license compliance checker.
    This is the script the GitHub Actions workflow invokes. It wires together
    the functions from LicenseChecker.psm1:

        1. Load the policy config   (allow-list / deny-list of licenses)
        2. Load the license database (the mock license-lookup data source)
        3. Build a compliance report for the requested manifest
        4. Print the report in a machine-parseable format
        5. Optionally fail the build when denied licenses are found

    Exit codes:
        0  success (report produced; denied licenses are only fatal with
                    -FailOnDenied)
        1  -FailOnDenied was supplied and at least one denied license found
        2  a fatal error occurred (bad input, parse failure, ...)
#>
[CmdletBinding()]
param(
    # Manifest to analyse (package.json or requirements.txt style).
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    # Policy config JSON exposing "allowList" and "denyList" arrays.
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    # Mock license database JSON: { "package": "SPDX-Id", ... }
    [Parameter()]
    [string]$LicenseDbPath,

    # Optional file to which the rendered report is also written.
    [Parameter()]
    [string]$OutputPath,

    # When set, exit non-zero if any dependency uses a denied license.
    [Parameter()]
    [switch]$FailOnDenied
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Import the core library next to this script (works from any CWD).
    Import-Module (Join-Path $PSScriptRoot 'LicenseChecker.psm1') -Force

    # --- Load policy config -------------------------------------------------
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: '$ConfigPath'"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    # Read the lists defensively: a config may legitimately define only one of
    # them, and StrictMode makes accessing a missing property an error.
    # Wrap the whole `if` in @(...) so a single-element or empty list is kept as
    # an array (a bare `$x = if {...} else {@()}` would unroll those to a scalar
    # or $null, breaking later `.Count` access under StrictMode).
    # Enumerate property names safely (an empty object's Properties collection
    # has no .Name member to dereference under StrictMode).
    $configProps = @($config.PSObject.Properties | ForEach-Object { $_.Name })
    $allowList = @(if ($configProps -contains 'allowList') { $config.allowList })
    $denyList  = @(if ($configProps -contains 'denyList')  { $config.denyList  })
    if ($allowList.Count -eq 0 -and $denyList.Count -eq 0) {
        throw "Config '$ConfigPath' must define 'allowList' and/or 'denyList'."
    }
    $policy = [pscustomobject]@{
        AllowList = $allowList
        DenyList  = $denyList
    }

    # --- Load the (mock) license database -----------------------------------
    $licenseDb = $null
    if ($LicenseDbPath) {
        if (-not (Test-Path -LiteralPath $LicenseDbPath -PathType Leaf)) {
            throw "License database file not found: '$LicenseDbPath'"
        }
        # -AsHashtable gives us the hashtable Get-DependencyLicense expects.
        $licenseDb = Get-Content -LiteralPath $LicenseDbPath -Raw | ConvertFrom-Json -AsHashtable
    }

    # --- Build & render the report ------------------------------------------
    $report = New-ComplianceReport -ManifestPath $ManifestPath -Config $policy -LicenseDatabase $licenseDb
    $lines  = Format-ComplianceReport -Report $report

    # Emit to stdout (captured by CI) and optionally to a file.
    $lines | ForEach-Object { Write-Output $_ }
    if ($OutputPath) {
        $lines | Set-Content -LiteralPath $OutputPath -Encoding utf8
    }

    if ($FailOnDenied -and $report.Summary.Denied -gt 0) {
        Write-Error "Found $($report.Summary.Denied) dependency/dependencies with denied licenses."
        exit 1
    }

    exit 0
}
catch {
    # Surface a meaningful, single-line error message and fail clearly.
    Write-Error "License check failed: $($_.Exception.Message)"
    exit 2
}
