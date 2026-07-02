<#
    .SYNOPSIS
    CLI entry point for the dependency license compliance check.

    .DESCRIPTION
    Parses a dependency manifest, resolves each dependency's license via the
    (mockable) lookup source, classifies it against an allow/deny policy, and
    prints a human-readable table plus machine-parsable lines so downstream
    tooling (or tests driving this via `act`) can assert on exact values.

    .PARAMETER ManifestPath
    Path to the dependency manifest (package.json or requirements*.txt).

    .PARAMETER ConfigPath
    Path to the JSON license policy file with "allowed" and "denied" arrays.

    .PARAMETER LicenseLookupPath
    Path to the JSON file mapping package name (or "name@version") to license.
    Stands in for a real registry lookup (npm/PyPI) so the CLI never requires
    network access.

    .PARAMETER FailOnDenied
    When set, the script exits with a non-zero code if any dependency's
    license is Denied. Off by default so the compliance report can always be
    generated and inspected even when it flags a problem.
#>
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LicenseLookupPath,

    [switch]$FailOnDenied
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DependencyLicenseChecker.psm1') -Force

try {
    $report = New-ComplianceReport -ManifestPath $ManifestPath -ConfigPath $ConfigPath -LicenseLookupPath $LicenseLookupPath
}
catch {
    Write-Error "Dependency license check failed: $($_.Exception.Message)"
    exit 1
}

Write-Host '::group::Dependency License Compliance Report'
$report | Format-Table -Property Name, Version, License, Status -AutoSize | Out-String | Write-Host
Write-Host '::endgroup::'

# Machine-parsable lines: stable format for downstream tooling/tests to assert exact values against.
foreach ($entry in $report) {
    Write-Host "REPORT_LINE|$($entry.Name)|$($entry.Version)|$($entry.License)|$($entry.Status)"
}

$approvedCount = ($report | Where-Object Status -eq 'Approved').Count
$deniedCount = ($report | Where-Object Status -eq 'Denied').Count
$unknownCount = ($report | Where-Object Status -eq 'Unknown').Count
$totalCount = $report.Count

Write-Host "SUMMARY|Approved=$approvedCount|Denied=$deniedCount|Unknown=$unknownCount|Total=$totalCount"

if ($env:GITHUB_STEP_SUMMARY) {
    $summaryLines = [System.Collections.Generic.List[string]]::new()
    $summaryLines.Add('## Dependency License Compliance Report')
    $summaryLines.Add('')
    $summaryLines.Add('| Name | Version | License | Status |')
    $summaryLines.Add('|------|---------|---------|--------|')
    foreach ($entry in $report) {
        $summaryLines.Add("| $($entry.Name) | $($entry.Version) | $($entry.License) | $($entry.Status) |")
    }
    $summaryLines.Add('')
    $summaryLines.Add("**Summary:** Approved=$approvedCount, Denied=$deniedCount, Unknown=$unknownCount, Total=$totalCount")
    $summaryLines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

if ($FailOnDenied -and $deniedCount -gt 0) {
    Write-Error "Compliance check failed: $deniedCount dependency(ies) have denied licenses."
    exit 1
}

exit 0
