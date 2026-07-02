<#
.SYNOPSIS
    Dependency license compliance checker.

.DESCRIPTION
    Parses dependency manifests (package.json, requirements.txt), looks up
    each dependency's license (against a mock license database file, standing
    in for a real registry API), classifies it against configured allow/deny
    lists, and produces a compliance report.

    Built incrementally with red/green TDD — see tests/ for the cycles.
#>

function Get-Dependencies {
    <#
    .SYNOPSIS
        Parse a dependency manifest into a list of Name/Version objects.
    .PARAMETER ManifestPath
        Path to the manifest file. Supported formats are detected from the
        file name: package.json (npm) and requirements.txt (pip).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'. Provide a path to an existing package.json or requirements.txt."
    }

    # Dispatch on the manifest file name; unknown formats fail loudly rather
    # than silently returning an empty report.
    switch -Wildcard ((Split-Path -Leaf $ManifestPath).ToLowerInvariant()) {
        'package.json'     { return ConvertFrom-PackageJson -Path $ManifestPath }
        '*requirements*.txt' { return ConvertFrom-RequirementsTxt -Path $ManifestPath }
        default {
            throw "Unsupported manifest format: '$(Split-Path -Leaf $ManifestPath)'. Supported: package.json, requirements.txt."
        }
    }
}

function ConvertFrom-PackageJson {
    # Internal: parse an npm package.json into Name/Version objects.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
    }

    $deps = [System.Collections.Generic.List[pscustomobject]]::new()
    # Collect both runtime and dev dependencies; each is a JSON object whose
    # properties are package names and values are semver ranges.
    foreach ($section in 'dependencies', 'devDependencies') {
        $block = $json.$section
        if ($null -eq $block) { continue }
        foreach ($prop in $block.PSObject.Properties) {
            $deps.Add([pscustomobject]@{
                Name    = $prop.Name
                # Strip range operators (^, ~, >=, etc.) to a bare version.
                Version = ([string]$prop.Value -replace '^[\^~><=\s]+', '')
            })
        }
    }
    return $deps
}

function ConvertFrom-RequirementsTxt {
    # Internal: parse a pip requirements.txt into Name/Version objects.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $deps = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($rawLine in Get-Content -Path $Path) {
        # Drop inline comments, then skip blank/comment-only lines.
        $line = ($rawLine -replace '#.*$', '').Trim()
        if (-not $line) { continue }

        # name[extras] <specifier> version — take the first specifier's version.
        if ($line -match '^(?<name>[A-Za-z0-9._-]+)(\[[^\]]*\])?\s*(==|>=|<=|~=|!=|>|<)\s*(?<version>[A-Za-z0-9.*+!-]+)') {
            $deps.Add([pscustomobject]@{ Name = $Matches.name; Version = $Matches.version })
        }
        elseif ($line -match '^(?<name>[A-Za-z0-9._-]+)(\[[^\]]*\])?$') {
            # Unpinned requirement — keep it, with an empty version.
            $deps.Add([pscustomobject]@{ Name = $Matches.name; Version = '' })
        }
        else {
            Write-Warning "Skipping unrecognized requirements line: '$rawLine'"
        }
    }
    return $deps
}

function Get-DependencyLicense {
    <#
    .SYNOPSIS
        Look up the license for a package.
    .DESCRIPTION
        Reads a JSON license database mapping package name -> SPDX license id.
        The database file is a MOCK of a real registry API (npm/PyPI), which
        keeps tests hermetic and CI offline-friendly. Returns $null when the
        package is not in the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [Parameter(Mandatory)]
        [string]$LicenseDatabasePath
    )

    if (-not (Test-Path -Path $LicenseDatabasePath -PathType Leaf)) {
        throw "License database not found: '$LicenseDatabasePath'."
    }

    try {
        $db = Get-Content -Path $LicenseDatabasePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse license database '$LicenseDatabasePath' as JSON: $($_.Exception.Message)"
    }

    $entry = $db.PSObject.Properties[$Name]
    if ($null -ne $entry) { return [string]$entry.Value }
    return $null
}

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Classify a license against allow/deny lists.
    .DESCRIPTION
        Returns 'denied' if the license is on the deny list (deny wins over
        allow), 'approved' if on the allow list, otherwise 'unknown'.
        A missing/empty license is always 'unknown'. Matching is
        case-insensitive.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()]
        [string]$License,

        [string[]]$Allow = @(),

        [string[]]$Deny = @()
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'unknown' }

    # -contains on string arrays is case-insensitive in PowerShell, which is
    # exactly the matching semantics we want for SPDX ids.
    if ($Deny -contains $License)  { return 'denied' }
    if ($Allow -contains $License) { return 'approved' }
    return 'unknown'
}

function Get-LicenseConfig {
    <#
    .SYNOPSIS
        Load the allow-list/deny-list configuration from a JSON file.
    .DESCRIPTION
        Expected shape: { "allow": ["MIT", ...], "deny": ["GPL-3.0", ...] }.
        Missing lists default to empty arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        throw "Config file not found: '$ConfigPath'."
    }

    try {
        $raw = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config '$ConfigPath' as JSON: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        Allow = @($raw.allow | Where-Object { $_ })
        Deny  = @($raw.deny  | Where-Object { $_ })
    }
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Build a compliance report for a set of dependencies.
    .DESCRIPTION
        For each dependency, resolves its license via Get-DependencyLicense
        (mockable in tests) and classifies it with Get-LicenseStatus.
        Returns objects with Name, Version, License and Status
        (approved | denied | unknown).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Dependencies,

        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$LicenseDatabasePath
    )

    $report = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($dep in $Dependencies) {
        $license = Get-DependencyLicense -Name $dep.Name -Version $dep.Version -LicenseDatabasePath $LicenseDatabasePath
        $status = Get-LicenseStatus -License $license -Allow $Config.Allow -Deny $Config.Deny
        $report.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            # Surface a stable placeholder instead of an empty cell so report
            # consumers can grep for it.
            License = if ([string]::IsNullOrWhiteSpace($license)) { 'UNKNOWN' } else { $license }
            Status  = $status
        })
    }
    return $report
}

function Invoke-LicenseCheck {
    <#
    .SYNOPSIS
        End-to-end pipeline: manifest + config + license database -> report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$LicenseDatabasePath
    )

    $dependencies = @(Get-Dependencies -ManifestPath $ManifestPath)
    $config = Get-LicenseConfig -ConfigPath $ConfigPath
    return New-ComplianceReport -Dependencies $dependencies -Config $config -LicenseDatabasePath $LicenseDatabasePath
}

Export-ModuleMember -Function Get-Dependencies, Get-DependencyLicense, Get-LicenseStatus, Get-LicenseConfig, New-ComplianceReport, Invoke-LicenseCheck
