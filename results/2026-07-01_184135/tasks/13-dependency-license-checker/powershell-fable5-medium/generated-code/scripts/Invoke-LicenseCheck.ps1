<#
.SYNOPSIS
    CLI entry point: generate a license compliance report for every manifest
    in a directory (or a single manifest file).

.DESCRIPTION
    Used by the GitHub Actions workflow. Finds package.json /
    requirements*.txt manifests, builds a compliance report for each using
    the mock JSON license database, and prints stable pipe-delimited lines:

        MANIFEST|<file>
        RESULT|<name>|<version>|<license>|<status>
        SUMMARY|Approved=..|Denied=..|Unknown=..|Total=..

.PARAMETER Path
    A manifest file or a directory to scan for manifests.

.PARAMETER ConfigPath
    JSON config with allowList / denyList arrays.

.PARAMETER LicenseDatabasePath
    JSON mock license database (package name -> license id).

.PARAMETER FailOnDenied
    Exit with code 2 if any dependency has a denied license.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LicenseDatabasePath,

    [switch]$FailOnDenied
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1') -Force

try {
    # Accept either a single manifest file or a directory of manifests.
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $manifests = @(Get-Item -LiteralPath $Path)
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $manifests = @(Get-ChildItem -LiteralPath $Path -File |
            Where-Object { $_.Name -eq 'package.json' -or $_.Name -like 'requirements*.txt' } |
            Sort-Object Name)
        if ($manifests.Count -eq 0) {
            throw "No supported manifests (package.json, requirements*.txt) found in directory '$Path'."
        }
    }
    else {
        throw "Path not found: '$Path'."
    }

    $deniedTotal = 0
    foreach ($manifest in $manifests) {
        $report = New-ComplianceReport -ManifestPath $manifest.FullName `
                                       -ConfigPath $ConfigPath `
                                       -LicenseDatabasePath $LicenseDatabasePath
        Format-ComplianceReport -Report $report | ForEach-Object { Write-Output $_ }
        $deniedTotal += $report.Summary.Denied
    }

    if ($FailOnDenied -and $deniedTotal -gt 0) {
        Write-Error -ErrorAction Continue "License check failed: $deniedTotal dependency(ies) with denied licenses."
        exit 2
    }
    exit 0
}
catch {
    Write-Error -ErrorAction Continue "License check error: $($_.Exception.Message)"
    exit 1
}
