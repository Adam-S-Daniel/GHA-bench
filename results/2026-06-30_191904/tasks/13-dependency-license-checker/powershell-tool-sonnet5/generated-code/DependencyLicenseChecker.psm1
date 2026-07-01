<#
    DependencyLicenseChecker

    Parses a dependency manifest (package.json or requirements.txt), looks up
    each dependency's license via a pluggable (mockable) lookup source, checks
    the license against an allow/deny policy, and produces a compliance report.
#>

function Get-Dependencies {
    <#
        .SYNOPSIS
        Extracts dependency name/version pairs from a manifest file.

        .DESCRIPTION
        Supports npm's package.json (dependencies + devDependencies) and
        pip's requirements.txt. The manifest format is chosen based on the
        file name.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: $ManifestPath"
    }

    $fileName = Split-Path -Leaf $ManifestPath

    if ($fileName -eq 'package.json') {
        return Get-DependenciesFromPackageJson -ManifestPath $ManifestPath
    }
    elseif ($fileName -like 'requirements*.txt') {
        return Get-DependenciesFromRequirementsTxt -ManifestPath $ManifestPath
    }
    else {
        throw "Unsupported manifest format: '$fileName'. Supported formats: package.json, requirements*.txt"
    }
}

function Get-DependenciesFromPackageJson {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    try {
        $json = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse package.json at '$ManifestPath': $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($section in 'dependencies', 'devDependencies') {
        if ($json.PSObject.Properties.Name -contains $section) {
            foreach ($prop in $json.$section.PSObject.Properties) {
                $results.Add([PSCustomObject]@{
                    Name    = $prop.Name
                    Version = (ConvertTo-CleanVersion -RawVersion $prop.Value)
                })
            }
        }
    }

    return $results
}

function Get-DependenciesFromRequirementsTxt {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $lines = Get-Content -LiteralPath $ManifestPath

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('-')) {
            continue
        }

        # Strip inline comments, e.g. "requests==2.31.0  # http client"
        $trimmed = ($trimmed -split '#')[0].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '^([A-Za-z0-9_.\-]+)\s*(==|>=|<=|~=|>|<)\s*([0-9A-Za-z.\-]+)') {
            $results.Add([PSCustomObject]@{
                Name    = $Matches[1]
                Version = $Matches[3]
            })
        }
        else {
            # No version pin at all, e.g. a bare package name
            $results.Add([PSCustomObject]@{
                Name    = $trimmed
                Version = ''
            })
        }
    }

    return $results
}

function ConvertTo-CleanVersion {
    <#
        .SYNOPSIS
        Strips npm semver range prefixes (^, ~, >=, etc.) to get a plain version.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RawVersion
    )

    return $RawVersion -replace '^[\^~>=<\s]+', ''
}

function Get-PackageLicense {
    <#
        .SYNOPSIS
        Looks up the license for a package.

        .DESCRIPTION
        This is the mockable seam for license lookup: in production, resolving
        a package's license typically requires querying a registry (npm,
        PyPI, etc.) over the network. Rather than hard-coding a network call,
        this function accepts a lookup table (Name or "Name@Version" -> license)
        so tests can inject fixture data and the CLI can inject a JSON file of
        cached/mocked results without any network access.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [Parameter(Mandatory)]
        [hashtable]$LicenseLookup
    )

    $versionedKey = "$Name@$Version"
    if ($LicenseLookup.ContainsKey($versionedKey)) {
        return $LicenseLookup[$versionedKey]
    }

    if ($LicenseLookup.ContainsKey($Name)) {
        return $LicenseLookup[$Name]
    }

    return 'UNKNOWN'
}

function Get-LicenseStatus {
    <#
        .SYNOPSIS
        Classifies a license as Approved, Denied, or Unknown per policy.

        .DESCRIPTION
        Deny-list is checked before allow-list so that an explicit deny always
        wins over an accidental overlap in configuration.
    #>
    param(
        [string]$License,

        [string[]]$AllowList = @(),

        [string[]]$DenyList = @()
    )

    if ([string]::IsNullOrWhiteSpace($License) -or $License -eq 'UNKNOWN') {
        return 'Unknown'
    }

    if ($DenyList -contains $License) {
        return 'Denied'
    }

    if ($AllowList -contains $License) {
        return 'Approved'
    }

    return 'Unknown'
}

function Get-LicensePolicy {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "License policy config not found: $ConfigPath"
    }

    try {
        $policy = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse license policy config at '$ConfigPath': $($_.Exception.Message)"
    }

    if (-not $policy.PSObject.Properties.Name -contains 'allowed') {
        throw "License policy config at '$ConfigPath' is missing required 'allowed' field."
    }
    if (-not $policy.PSObject.Properties.Name -contains 'denied') {
        throw "License policy config at '$ConfigPath' is missing required 'denied' field."
    }

    return $policy
}

function Get-LicenseLookupTable {
    param(
        [Parameter(Mandatory)]
        [string]$LicenseLookupPath
    )

    if (-not (Test-Path -LiteralPath $LicenseLookupPath -PathType Leaf)) {
        throw "License lookup data not found: $LicenseLookupPath"
    }

    try {
        $raw = Get-Content -LiteralPath $LicenseLookupPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse license lookup data at '$LicenseLookupPath': $($_.Exception.Message)"
    }

    $table = @{}
    foreach ($prop in $raw.PSObject.Properties) {
        $table[$prop.Name] = $prop.Value
    }

    return $table
}

function New-ComplianceReport {
    <#
        .SYNOPSIS
        Parses a manifest, resolves each dependency's license, and classifies
        it against the configured allow/deny policy.

        .OUTPUTS
        An array of PSCustomObject with Name, Version, License, Status.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$LicenseLookupPath
    )

    $policy = Get-LicensePolicy -ConfigPath $ConfigPath
    $lookupTable = Get-LicenseLookupTable -LicenseLookupPath $LicenseLookupPath
    $dependencies = Get-Dependencies -ManifestPath $ManifestPath

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($dep in $dependencies) {
        $license = Get-PackageLicense -Name $dep.Name -Version $dep.Version -LicenseLookup $lookupTable
        $status = Get-LicenseStatus -License $license -AllowList $policy.allowed -DenyList $policy.denied

        $results.Add([PSCustomObject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        })
    }

    return $results
}

Export-ModuleMember -Function Get-Dependencies, Get-PackageLicense, Get-LicenseStatus, New-ComplianceReport, Get-LicensePolicy, Get-LicenseLookupTable
