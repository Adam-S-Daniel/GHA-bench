<#
.SYNOPSIS
    Dependency License Checker.

.DESCRIPTION
    Parses a dependency manifest (package.json or requirements.txt), looks up the
    license for each dependency, and evaluates it against an allow-list / deny-list
    of licenses to produce a compliance report.

    The license lookup (Get-DependencyLicense -> Get-LicenseFromDatabase) is
    intentionally factored so it can be mocked in tests or backed by a static
    JSON database in CI, avoiding any dependency on an external network service.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Manifest parsing

function Get-DependencyList {
    <#
    .SYNOPSIS
        Parse a dependency manifest into a list of dependency objects.
    .DESCRIPTION
        Supports package.json (npm) and requirements.txt (pip). The manifest type
        is inferred from the file name. Each returned object has Name, Version and
        Scope ('prod' or 'dev') properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $fileName = Split-Path -Path $ManifestPath -Leaf

    switch -Regex ($fileName) {
        '(^|/)package\.json$' { return Get-DependencyListFromPackageJson -Path $ManifestPath }
        'requirements.*\.txt$' { return Get-DependencyListFromRequirements -Path $ManifestPath }
        default {
            throw "Unsupported manifest type: '$fileName'. Supported: package.json, requirements.txt"
        }
    }
}

function Get-DependencyListFromPackageJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse package.json '$Path': $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[object]]::new()

    # Helper to walk a dependency map (name -> version range) with a given scope.
    $addDeps = {
        param($map, $scope)
        if ($null -eq $map) { return }
        foreach ($prop in $map.PSObject.Properties) {
            $results.Add([pscustomobject]@{
                Name    = $prop.Name
                Version = ConvertTo-CleanVersion -Version $prop.Value
                Scope   = $scope
            })
        }
    }

    $deps    = if ($json.PSObject.Properties.Name -contains 'dependencies') { $json.dependencies } else { $null }
    $devDeps = if ($json.PSObject.Properties.Name -contains 'devDependencies') { $json.devDependencies } else { $null }

    & $addDeps $deps 'prod'
    & $addDeps $devDeps 'dev'

    return $results.ToArray()
}

function Get-DependencyListFromRequirements {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $trimmed = $line.Trim()
        # Skip blank lines and comments.
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

        # Match: name <operator> version  (e.g. requests==2.31.0, flask>=2.3.0, numpy~=1.24.0)
        if ($trimmed -match '^(?<name>[A-Za-z0-9_.\-]+)\s*(==|>=|<=|~=|>|<)\s*(?<version>[^\s;#]+)') {
            $results.Add([pscustomobject]@{
                Name    = $Matches['name']
                Version = ConvertTo-CleanVersion -Version $Matches['version']
                Scope   = 'prod'
            })
        }
    }

    return $results.ToArray()
}

function ConvertTo-CleanVersion {
    <#
    .SYNOPSIS
        Strip semver range operators (^, ~, >=, etc.) to a bare version string.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Version)

    return ($Version -replace '^[\^~><=!\s]+', '').Trim()
}

#endregion

#region License lookup (mockable)

function Get-LicenseFromDatabase {
    <#
    .SYNOPSIS
        Low-level license lookup against a static JSON database.
    .DESCRIPTION
        Factored out as its own function so tests can Mock it to simulate an
        external license service without touching the filesystem.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        throw "License database not found: '$DatabasePath'"
    }

    try {
        $db = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse license database '$DatabasePath': $($_.Exception.Message)"
    }

    if ($db.PSObject.Properties.Name -contains $Name) {
        return [string]$db.$Name
    }

    return $null
}

function Get-DependencyLicense {
    <#
    .SYNOPSIS
        Look up the SPDX license identifier for a dependency.
    .DESCRIPTION
        Returns the license string, or 'UNKNOWN' when the dependency cannot be
        resolved. Delegates the actual lookup to Get-LicenseFromDatabase, which
        is the seam used for mocking in tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    $license = Get-LicenseFromDatabase -Name $Name -Version $Version -DatabasePath $DatabasePath

    if ([string]::IsNullOrWhiteSpace($license)) {
        return 'UNKNOWN'
    }

    return $license
}

#endregion

#region Compliance evaluation

function Test-LicenseStatus {
    <#
    .SYNOPSIS
        Classify a license against the allow-list and deny-list.
    .OUTPUTS
        'Approved', 'Denied', or 'Unknown'. The deny-list always wins; an
        unresolved ('UNKNOWN') license is always 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$License,
        [string[]]$AllowList = @(),
        [string[]]$DenyList = @()
    )

    if ($License -eq 'UNKNOWN') { return 'Unknown' }

    # Case-insensitive comparison sets.
    $deny  = [System.Collections.Generic.HashSet[string]]::new([string[]]$DenyList,  [System.StringComparer]::OrdinalIgnoreCase)
    $allow = [System.Collections.Generic.HashSet[string]]::new([string[]]$AllowList, [System.StringComparer]::OrdinalIgnoreCase)

    # Deny-list takes precedence over allow-list.
    if ($deny.Contains($License))  { return 'Denied' }
    if ($allow.Contains($License)) { return 'Approved' }

    return 'Unknown'
}

#endregion

#region Report orchestration

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Build a full compliance report for a manifest.
    .DESCRIPTION
        Parses the manifest, resolves each dependency's license, evaluates its
        status, and returns an object with per-dependency Results, a Summary of
        counts by status, and an overall Compliant flag (false if anything is
        Denied).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: '$ConfigPath'"
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config '$ConfigPath': $($_.Exception.Message)"
    }

    $allowList = @(if ($config.PSObject.Properties.Name -contains 'allowList') { $config.allowList })
    $denyList  = @(if ($config.PSObject.Properties.Name -contains 'denyList')  { $config.denyList })

    $dependencies = Get-DependencyList -ManifestPath $ManifestPath

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in $dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -Version $dep.Version -DatabasePath $DatabasePath
        $status  = Test-LicenseStatus -License $license -AllowList $allowList -DenyList $denyList

        $results.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            Scope   = $dep.Scope
            License = $license
            Status  = $status
        })
    }

    $summary = [pscustomobject]@{
        Approved = @($results | Where-Object Status -eq 'Approved').Count
        Denied   = @($results | Where-Object Status -eq 'Denied').Count
        Unknown  = @($results | Where-Object Status -eq 'Unknown').Count
        Total    = $results.Count
    }

    return [pscustomobject]@{
        Manifest  = $ManifestPath
        Results   = $results.ToArray()
        Summary   = $summary
        Compliant = ($summary.Denied -eq 0)
    }
}

#endregion

Export-ModuleMember -Function @(
    'Get-DependencyList',
    'Get-DependencyLicense',
    'Get-LicenseFromDatabase',
    'Test-LicenseStatus',
    'New-ComplianceReport'
)
