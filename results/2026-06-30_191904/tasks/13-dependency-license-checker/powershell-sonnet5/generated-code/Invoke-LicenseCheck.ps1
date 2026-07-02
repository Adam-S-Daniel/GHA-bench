<#
    .SYNOPSIS
    CLI entry point for the dependency license compliance checker. Run by
    the GitHub Actions workflow to print a report against a manifest,
    a license policy (allow/deny lists), and a license database.

    .DESCRIPTION
    Exits 0 for a successful report -- even one that contains Denied
    dependencies, since the point of this tool is to *report* compliance
    status, not to gate the build. It exits 1 only on genuine operational
    errors (missing/malformed input files), each with a clear message.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ManifestPath = 'package.json',

    [Parameter()]
    [string]$PolicyPath = 'license-policy.json',

    [Parameter()]
    [string]$LicenseDatabasePath = 'license-database.json'
)

Import-Module (Join-Path $PSScriptRoot 'LicenseChecker.psm1') -Force

try {
    $report = New-LicenseComplianceReport -ManifestPath $ManifestPath -PolicyPath $PolicyPath -LicenseDatabasePath $LicenseDatabasePath
}
catch {
    Write-Error -Message "Dependency license check failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}

Write-Output '=== Dependency License Compliance Report ==='
$report.Dependencies | Format-Table -Property Name, Version, License, Status -AutoSize | Out-String | Write-Output

Write-Output ("Summary: Approved={0}, Denied={1}, Unknown={2}" -f $report.Summary.Approved, $report.Summary.Denied, $report.Summary.Unknown)

if ($report.Summary.Denied -gt 0) {
    Write-Warning "$($report.Summary.Denied) dependency(ies) use a denied license. Review the report above."
}

exit 0
