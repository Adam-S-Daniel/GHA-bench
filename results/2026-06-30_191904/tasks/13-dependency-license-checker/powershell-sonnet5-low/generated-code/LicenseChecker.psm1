# Dependency license compliance checker.
# Parses a manifest, looks up each dependency's license (via a pluggable/mockable
# lookup function), classifies it against an allow/deny policy, and produces
# a compliance report.

function Get-ManifestDependencies {
    <#
        Parses a dependency manifest file and returns objects with Name/Version.
        Supports package.json (dependencies + devDependencies) and requirements.txt.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    $fileName = [System.IO.Path]::GetFileName($Path)

    $results = [System.Collections.Generic.List[object]]::new()

    if ($fileName -like '*.json') {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

        foreach ($section in @('dependencies', 'devDependencies')) {
            if ($json.PSObject.Properties.Name -contains $section) {
                foreach ($prop in $json.$section.PSObject.Properties) {
                    $results.Add([pscustomobject]@{
                        Name    = $prop.Name
                        Version = $prop.Value
                    })
                }
            }
        }
    }
    elseif ($fileName -like '*.txt') {
        foreach ($line in Get-Content -LiteralPath $Path) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }
            if ($trimmed -match '^([A-Za-z0-9_.\-]+)\s*==\s*([A-Za-z0-9_.\-]+)') {
                $results.Add([pscustomobject]@{
                    Name    = $Matches[1]
                    Version = $Matches[2]
                })
            }
        }
    }
    else {
        throw "Unsupported manifest type: '$fileName'. Supported types are package.json and requirements.txt."
    }

    return $results
}

function Get-LicensePolicy {
    <#
        Loads an allow-list/deny-list license policy from a JSON file.
        Returns a hashtable with Allow and Deny string arrays.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License policy file not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return @{
        Allow = @($json.Allow)
        Deny  = @($json.Deny)
    }
}

function Resolve-DependencyLicense {
    <#
        Resolves the license for a single dependency using a pluggable lookup
        function (so real HTTP/registry lookups can be swapped for mocks in tests).
        Any failure or empty result is normalized to 'Unknown' rather than throwing,
        since a single bad lookup should not abort the whole report.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [scriptblock] $LookupFunction
    )

    try {
        $license = & $LookupFunction $Name $Version
        if ([string]::IsNullOrWhiteSpace($license)) {
            return 'Unknown'
        }
        return $license
    }
    catch {
        return 'Unknown'
    }
}

function Get-LicenseStatus {
    <#
        Classifies a license string against an allow/deny policy.
    #>
    param(
        [Parameter(Mandatory)] [string] $License,
        [Parameter(Mandatory)] [hashtable] $Policy
    )

    if ($License -eq 'Unknown') {
        return 'Unknown'
    }
    if ($Policy.Deny -contains $License) {
        return 'Denied'
    }
    if ($Policy.Allow -contains $License) {
        return 'Approved'
    }
    return 'Unknown'
}

function New-ComplianceReport {
    <#
        Builds a compliance report: one row per dependency with its resolved
        license and Approved/Denied/Unknown status.
    #>
    param(
        [Parameter(Mandatory)] [object[]] $Dependencies,
        [Parameter(Mandatory)] [hashtable] $Policy,
        [Parameter(Mandatory)] [scriptblock] $LookupFunction
    )

    $report = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in $Dependencies) {
        $license = Resolve-DependencyLicense -Name $dep.Name -Version $dep.Version -LookupFunction $LookupFunction
        $status = Get-LicenseStatus -License $license -Policy $Policy
        $report.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        })
    }
    return $report
}

function Test-ComplianceViolations {
    <#
        Returns $true if any row in the report has a Denied status.
    #>
    param(
        [Parameter(Mandatory)] [object[]] $Report
    )

    return [bool]($Report | Where-Object { $_.Status -eq 'Denied' })
}

Export-ModuleMember -Function `
    Get-ManifestDependencies, `
    Get-LicensePolicy, `
    Resolve-DependencyLicense, `
    Get-LicenseStatus, `
    New-ComplianceReport, `
    Test-ComplianceViolations
