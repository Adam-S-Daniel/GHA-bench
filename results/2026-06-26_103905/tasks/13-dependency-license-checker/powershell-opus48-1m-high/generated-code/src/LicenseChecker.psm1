# LicenseChecker.psm1
#
# Core logic for the dependency license compliance checker.
#
# The module is intentionally split into small, single-responsibility functions
# so each can be unit-tested in isolation:
#
#   Get-Dependencies        parse a manifest into name/version records
#   Resolve-DependencyLicense  look up a dependency's license (mockable)
#   Get-LicenseStatus       classify a license as approved/denied/unknown
#   New-ComplianceReport    orchestrate the above into a full report
#
# Every function uses [CmdletBinding()] and throws descriptive errors so failures
# surface meaningful messages rather than null-reference noise.

Set-StrictMode -Version Latest

function Get-Dependencies {
    <#
    .SYNOPSIS
        Parse a dependency manifest and return name/version records.

    .DESCRIPTION
        Supports npm `package.json` (dependencies + devDependencies) and
        Python `requirements.txt` (name==version). The manifest type is
        detected from the file name. Version range markers commonly found in
        npm specs (^, ~, >=, etc.) are stripped so the bare version remains.

    .PARAMETER ManifestPath
        Path to the manifest file.

    .OUTPUTS
        [pscustomobject] with Name and Version properties, one per dependency.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $fileName = Split-Path -Leaf $ManifestPath

    if ($fileName -ieq 'package.json') {
        return Get-DependenciesFromPackageJson -ManifestPath $ManifestPath
    }
    elseif ($fileName -imatch 'requirements.*\.txt$' -or $fileName -ieq 'requirements.txt') {
        return Get-DependenciesFromRequirements -ManifestPath $ManifestPath
    }
    else {
        throw "Unsupported manifest type: '$fileName'. Supported: package.json, requirements.txt"
    }
}

function Get-DependenciesFromPackageJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath)

    try {
        $raw  = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse package.json '$ManifestPath': $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($section in 'dependencies', 'devDependencies') {
        if ($json.PSObject.Properties.Name -contains $section -and $null -ne $json.$section) {
            foreach ($prop in $json.$section.PSObject.Properties) {
                $results.Add([pscustomobject]@{
                    Name    = $prop.Name
                    Version = ConvertTo-BareVersion $prop.Value
                })
            }
        }
    }

    return $results.ToArray()
}

function Get-DependenciesFromRequirements {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($line in (Get-Content -LiteralPath $ManifestPath)) {
        $trimmed = $line.Trim()
        # Skip blank lines, comments, and pip options like -r / --hash.
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('-')) {
            continue
        }

        # Split on the first version specifier (==, >=, <=, ~=, >, <, !=).
        if ($trimmed -match '^(?<name>[A-Za-z0-9_.\-]+)\s*(?<op>==|>=|<=|~=|!=|>|<)?\s*(?<ver>[A-Za-z0-9_.\-]+)?') {
            $results.Add([pscustomobject]@{
                Name    = $Matches['name']
                Version = if ($Matches['ver']) { ConvertTo-BareVersion $Matches['ver'] } else { '' }
            })
        }
    }

    return $results.ToArray()
}

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Classify a license string against an allow-list and a deny-list.

    .DESCRIPTION
        Returns one of:
          'denied'   - license appears on the deny-list (deny wins over allow)
          'approved' - license appears on the allow-list
          'unknown'  - license is empty, or on neither list

        Matching is case-insensitive. The deny-list is authoritative: if a
        license somehow appears on both lists it is reported as denied, which is
        the safe/conservative default for a compliance gate.

    .PARAMETER License
        The SPDX-style license identifier to classify (may be empty/null).

    .PARAMETER AllowList
        Licenses that are explicitly approved.

    .PARAMETER DenyList
        Licenses that are explicitly forbidden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$License,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$AllowList,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$DenyList
    )

    if ([string]::IsNullOrWhiteSpace($License)) {
        return 'unknown'
    }

    $normalized = $License.Trim()

    # Deny-list checked first so it takes precedence over the allow-list.
    if ($DenyList | Where-Object { $_ -ieq $normalized }) {
        return 'denied'
    }
    if ($AllowList | Where-Object { $_ -ieq $normalized }) {
        return 'approved'
    }

    return 'unknown'
}

function Resolve-DependencyLicense {
    <#
    .SYNOPSIS
        Look up the license for a dependency. This is the mockable seam.

    .DESCRIPTION
        In a real deployment this would query the npm registry, PyPI, or a SBOM
        service over the network. For deterministic, offline operation (tests and
        CI) it instead reads from a supplied in-memory license database keyed by
        package name. Pester `Mock`s this function to inject fixed responses.

    .PARAMETER Name
        Dependency package name.

    .PARAMETER Version
        Dependency version (accepted for signature realism / future per-version
        lookups; the mock database is keyed by name only).

    .PARAMETER LicenseDatabase
        Hashtable mapping package name -> SPDX license id.

    .OUTPUTS
        The license identifier, or 'UNKNOWN' if the package is not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][string]$Version = '',
        [Parameter(Mandatory)][hashtable]$LicenseDatabase
    )

    # Case-insensitive lookup over the database keys.
    foreach ($key in $LicenseDatabase.Keys) {
        if ($key -ieq $Name) {
            $value = $LicenseDatabase[$key]
            if ([string]::IsNullOrWhiteSpace($value)) { return 'UNKNOWN' }
            return $value
        }
    }

    return 'UNKNOWN'
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Build a full license-compliance report from a dependency list.

    .DESCRIPTION
        For each dependency it resolves the license (via Resolve-DependencyLicense
        so the lookup can be mocked) and classifies it (via Get-LicenseStatus)
        against the allow/deny lists in $Config. Returns a structured report with
        per-dependency items, status counts, and an overall Compliant flag
        (false if any dependency is denied).

    .PARAMETER Dependencies
        Objects with Name and Version properties (e.g. from Get-Dependencies).

    .PARAMETER Config
        Object/hashtable exposing `allow` and `deny` string arrays.

    .PARAMETER LicenseDatabase
        Optional hashtable passed through to Resolve-DependencyLicense. When the
        lookup is mocked (tests) this can be omitted.

    .OUTPUTS
        [pscustomobject] with Items, Summary, and Compliant properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Dependencies,

        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter()]
        [hashtable]$LicenseDatabase = @{}
    )

    # Normalize allow/deny lists from either a PSCustomObject or a hashtable.
    $allow = @(Get-ConfigList -Config $Config -Key 'allow')
    $deny  = @(Get-ConfigList -Config $Config -Key 'deny')

    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($dep in $Dependencies) {
        $license = Resolve-DependencyLicense -Name $dep.Name -Version $dep.Version -LicenseDatabase $LicenseDatabase
        $status  = Get-LicenseStatus -License $license -AllowList $allow -DenyList $deny

        $items.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        })
    }

    $approved = @($items | Where-Object Status -eq 'approved').Count
    $denied   = @($items | Where-Object Status -eq 'denied').Count
    $unknown  = @($items | Where-Object Status -eq 'unknown').Count

    return [pscustomobject]@{
        Items     = $items.ToArray()
        Summary   = [pscustomobject]@{
            Total    = $items.Count
            Approved = $approved
            Denied   = $denied
            Unknown  = $unknown
        }
        # Conservative gate: denied dependencies break compliance. Unknown
        # licenses are surfaced but do not by themselves fail the report.
        Compliant = ($denied -eq 0)
    }
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Render a compliance report (from New-ComplianceReport) as plain text.

    .DESCRIPTION
        Produces a stable, human-readable, line-oriented report. The format is a
        contract consumed by the CI pipeline's assertions, so it is kept simple
        and deterministic:

            Dependency License Compliance Report
            ====================================
            <name>@<version> [<LICENSE>] -> <STATUS>
            ...
            ------------------------------------
            Total: N | Approved: A | Denied: D | Unknown: U
            Compliance: PASS|FAIL

    .PARAMETER Report
        The object returned by New-ComplianceReport.

    .OUTPUTS
        A single multi-line string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Dependency License Compliance Report')
    $lines.Add('====================================')

    foreach ($item in $Report.Items) {
        $lines.Add(('{0}@{1} [{2}] -> {3}' -f $item.Name, $item.Version, $item.License, $item.Status.ToUpper()))
    }

    $lines.Add('------------------------------------')
    $lines.Add(('Total: {0} | Approved: {1} | Denied: {2} | Unknown: {3}' -f `
        $Report.Summary.Total, $Report.Summary.Approved, $Report.Summary.Denied, $Report.Summary.Unknown))
    $lines.Add(('Compliance: {0}' -f $(if ($Report.Compliant) { 'PASS' } else { 'FAIL' })))

    return ($lines -join [Environment]::NewLine)
}

function Get-ConfigList {
    <#
    .SYNOPSIS
        Read a named string-array key from a config object or hashtable, tolerant
        of missing keys (returns an empty array).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$Key
    )

    if ($null -eq $Config) { return @() }

    if ($Config -is [hashtable]) {
        if ($Config.ContainsKey($Key) -and $null -ne $Config[$Key]) { return @($Config[$Key]) }
        return @()
    }

    # PSCustomObject path
    $prop = $Config.PSObject.Properties[$Key]
    if ($prop -and $null -ne $prop.Value) { return @($prop.Value) }
    return @()
}

function ConvertTo-BareVersion {
    <#
    .SYNOPSIS
        Strip npm/pip range operators from a version spec, leaving the version.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$VersionSpec)

    # Remove a leading operator (^ ~ >= <= ~= != > < =) and surrounding spaces.
    return ($VersionSpec -replace '^[\s\^~><=!]+', '').Trim()
}
