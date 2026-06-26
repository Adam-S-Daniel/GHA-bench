<#
.SYNOPSIS
    Dependency License Checker module.

.DESCRIPTION
    Parses a dependency manifest (package.json or requirements.txt), looks up the
    license for each dependency, and classifies it against an allow-list and a
    deny-list of licenses. The license lookup is isolated in its own function so
    it can be mocked during testing and swapped for a real registry call in
    production.

    Functions are intentionally small and single-purpose so each one could be
    driven out by its own failing test (red/green TDD).
#>

Set-StrictMode -Version Latest

function Get-Dependencies {
    <#
    .SYNOPSIS
        Parse a dependency manifest into a list of name/version objects.
    .PARAMETER Path
        Path to the manifest file. The manifest type is inferred from the file name.
    .OUTPUTS
        [pscustomobject] with Name and Version properties, one per dependency.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: '$Path'"
    }

    $fileName = Split-Path -Path $Path -Leaf

    # Detect the manifest type by extension so variants like `package-denied.json`
    # or `dev-requirements.txt` are handled as their respective formats.
    switch -Wildcard ($fileName) {
        '*.json' {
            return Get-DependenciesFromPackageJson -Path $Path
        }
        '*requirements*.txt' {
            return Get-DependenciesFromRequirements -Path $Path
        }
        'requirements.txt' {
            return Get-DependenciesFromRequirements -Path $Path
        }
        default {
            throw "Unsupported manifest type: '$fileName'. Supported: package.json (*.json), requirements.txt."
        }
    }
}

function Get-DependenciesFromPackageJson {
    # Reads npm dependencies + devDependencies and normalises versions.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse package.json '$Path': $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($section in 'dependencies', 'devDependencies') {
        if ($json.PSObject.Properties.Name -contains $section -and $null -ne $json.$section) {
            foreach ($prop in $json.$section.PSObject.Properties) {
                $results.Add([pscustomobject]@{
                    Name    = $prop.Name
                    Version = ConvertTo-CleanVersion $prop.Value
                })
            }
        }
    }

    return $results.ToArray()
}

function Get-DependenciesFromRequirements {
    # Reads a pip requirements file. Supports ==, >=, <=, ~=, > and < operators.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()

        # Skip blank lines and comments.
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        # Split on the first version specifier we encounter.
        if ($line -match '^(?<name>[A-Za-z0-9._-]+)\s*(?:==|>=|<=|~=|!=|>|<)\s*(?<version>[^\s,;#]+)') {
            $results.Add([pscustomobject]@{
                Name    = $Matches['name']
                Version = $Matches['version']
            })
        }
        elseif ($line -match '^(?<name>[A-Za-z0-9._-]+)$') {
            # Unpinned dependency (no version specifier).
            $results.Add([pscustomobject]@{
                Name    = $Matches['name']
                Version = ''
            })
        }
    }

    return $results.ToArray()
}

function ConvertTo-CleanVersion {
    # Strip semver range operators (^, ~, >=, <=, etc.) leaving the bare version.
    [CmdletBinding()]
    param([string] $Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    return ($Raw -replace '^[\^~><=!\s]+', '').Trim()
}

function Get-LicenseConfig {
    <#
    .SYNOPSIS
        Load the allow-list / deny-list of licenses from a JSON config file.
    .OUTPUTS
        [pscustomobject] with Allow and Deny string-array properties.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License config file not found: '$Path'"
    }

    try {
        $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse license config '$Path': $($_.Exception.Message)"
    }

    # Coerce to arrays so callers always get a consistent shape, even for a single entry.
    return [pscustomobject]@{
        Allow = @($cfg.allow)
        Deny  = @($cfg.deny)
    }
}

function Test-LicenseStatus {
    <#
    .SYNOPSIS
        Classify a single license as approved / denied / unknown.
    .DESCRIPTION
        Deny-list wins over allow-list (fail-safe): if a license appears on both,
        it is denied. An empty/null license is "unknown".
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $License,

        [string[]] $AllowList = @(),
        [string[]] $DenyList  = @()
    )

    if ([string]::IsNullOrWhiteSpace($License)) {
        return 'unknown'
    }

    # Deny takes precedence — checked first.
    if ($DenyList -contains $License)  { return 'denied' }
    if ($AllowList -contains $License) { return 'approved' }
    return 'unknown'
}

function Get-DependencyLicense {
    <#
    .SYNOPSIS
        Look up the license for a dependency.
    .DESCRIPTION
        In tests this function is mocked. In production it is backed by a license
        database (a hashtable mapping dependency name -> SPDX license id), which is
        loaded from a JSON file by the CLI entry point. Unknown packages resolve to
        the sentinel "UNKNOWN".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Version,
        [hashtable] $Database = @{}
    )

    if ($Database.ContainsKey($Name)) {
        return [string] $Database[$Name]
    }
    return 'UNKNOWN'
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Build the full compliance report for a manifest.
    .OUTPUTS
        One [pscustomobject] per dependency with Name, Version, License, Status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ManifestPath,
        [Parameter(Mandatory)][string] $ConfigPath,
        [hashtable] $LicenseDatabase = @{}
    )

    $deps   = Get-Dependencies   -Path $ManifestPath
    $config = Get-LicenseConfig  -Path $ConfigPath

    $report = foreach ($dep in $deps) {
        $license = Get-DependencyLicense -Name $dep.Name -Version $dep.Version -Database $LicenseDatabase
        $status  = Test-LicenseStatus -License $license -AllowList $config.Allow -DenyList $config.Deny

        [pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        }
    }

    return @($report)
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Render a compliance report as human-readable text with a summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('=== Dependency License Compliance Report ===')
    $lines.Add('')

    foreach ($row in $Report) {
        $lines.Add(('{0,-25} {1,-12} {2,-15} {3}' -f $row.Name, $row.Version, $row.License, $row.Status.ToUpper()))
    }

    $approved = @($Report | Where-Object Status -eq 'approved').Count
    $denied   = @($Report | Where-Object Status -eq 'denied').Count
    $unknown  = @($Report | Where-Object Status -eq 'unknown').Count

    $lines.Add('')
    $lines.Add('--- Summary ---')
    $lines.Add("Total:    $($Report.Count)")
    $lines.Add("Approved: $approved")
    $lines.Add("Denied:   $denied")
    $lines.Add("Unknown:  $unknown")

    return $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function Get-Dependencies, Get-LicenseConfig, Test-LicenseStatus,
    Get-DependencyLicense, New-ComplianceReport, Format-ComplianceReport
