#requires -Version 7.0
<#
    .SYNOPSIS
    CI entry point: parses a dependency manifest, checks each dependency's
    license against an allow/deny config, and prints a compliance report.

    .DESCRIPTION
    Runs entirely offline: license data comes from a local JSON "database"
    file (fixtures/license-database.json) rather than a live registry call,
    so this can run inside a GitHub Actions job without network access to
    external package registries.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$DatabasePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LicenseChecker.psm1') -Force

foreach ($p in @($ConfigPath, $DatabasePath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "Required file not found: '$p'"
    }
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$database = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json

$report = New-ComplianceReport -ManifestPath $ManifestPath -Config $config -LicenseDatabase $database

Write-Host ''
Write-Host '=== Dependency License Compliance Report ==='
$report | Format-Table -AutoSize | Out-String | Write-Host

$approved = @($report | Where-Object { $_.Status -eq 'Approved' }).Count
$denied = @($report | Where-Object { $_.Status -eq 'Denied' }).Count
$unknown = @($report | Where-Object { $_.Status -eq 'Unknown' }).Count

Write-Host "Summary: $approved approved, $denied denied, $unknown unknown (total $($report.Count))"

$markdown = Format-ComplianceReport -Report $report
if ($env:GITHUB_STEP_SUMMARY) {
    "## Dependency License Compliance Report`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    $markdown | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    "`nSummary: $approved approved, $denied denied, $unknown unknown (total $($report.Count))" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
