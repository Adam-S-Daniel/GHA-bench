# CLI entry point: parses a manifest, checks licenses against a policy,
# prints a compliance report, and exits non-zero if any dependency is Denied.
#
# In CI we mock the license lookup with a small fixture map (LicenseFixture.json)
# since real registry lookups would require network access and are not
# deterministic enough for a reproducible pipeline.
param(
    [Parameter(Mandatory)] [string] $ManifestPath,
    [Parameter(Mandatory)] [string] $PolicyPath,
    [string] $LicenseFixturePath = "$PSScriptRoot/fixtures/license-lookup.json"
)

Import-Module "$PSScriptRoot/LicenseChecker.psm1" -Force

try {
    $dependencies = Get-ManifestDependencies -Path $ManifestPath
    $policy = Get-LicensePolicy -Path $PolicyPath

    $fixtureMap = @{}
    if (Test-Path -LiteralPath $LicenseFixturePath) {
        (Get-Content -LiteralPath $LicenseFixturePath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $fixtureMap[$_.Name] = $_.Value }
    }

    $lookup = {
        param($Name, $Version)
        if ($fixtureMap.ContainsKey($Name)) { return $fixtureMap[$Name] }
        return $null
    }.GetNewClosure()

    $report = New-ComplianceReport -Dependencies $dependencies -Policy $policy -LookupFunction $lookup

    Write-Output '=== Dependency License Compliance Report ==='
    $report | Format-Table -AutoSize | Out-String | Write-Output

    $approved = @($report | Where-Object Status -eq 'Approved').Count
    $denied = @($report | Where-Object Status -eq 'Denied').Count
    $unknown = @($report | Where-Object Status -eq 'Unknown').Count
    Write-Output "Summary: Approved=$approved Denied=$denied Unknown=$unknown"

    if (Test-ComplianceViolations -Report $report) {
        Write-Output 'RESULT: FAIL - one or more dependencies use a denied license.'
        exit 1
    }

    Write-Output 'RESULT: PASS - no denied licenses found.'
    exit 0
}
catch {
    Write-Error "License check failed: $($_.Exception.Message)"
    exit 2
}
