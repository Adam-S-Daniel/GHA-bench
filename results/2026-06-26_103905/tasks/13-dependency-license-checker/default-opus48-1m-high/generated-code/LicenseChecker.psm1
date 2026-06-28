<#
    LicenseChecker.psm1

    Core logic for the Dependency License Checker.

    Functions are intentionally small and single-purpose so they can be unit
    tested in isolation. Get-DependencyLicense is the seam we mock in tests:
    in production it reads from a local license database file (a stand-in for
    a real registry API); in tests it is replaced by a Pester Mock.
#>

Set-StrictMode -Version Latest

function Get-Dependencies {
    <#
        .SYNOPSIS
            Parse a dependency manifest and return its dependencies.
        .DESCRIPTION
            Supports package.json (npm) and requirements.txt (pip). Returns a
            list of objects with Name and Version properties. Semver range
            operators (^ ~ >= <= == > < =) are stripped to leave a bare version.
        .PARAMETER ManifestPath
            Path to the manifest file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest file not found: '$ManifestPath'"
    }

    $fileName = Split-Path -Leaf $ManifestPath

    switch -Regex ($fileName) {
        'package\.json$' { return Get-DependenciesFromPackageJson -Path $ManifestPath }
        'requirements.*\.txt$' { return Get-DependenciesFromRequirements -Path $ManifestPath }
        default {
            throw "Unsupported manifest type: '$fileName'. Supported: package.json, requirements.txt"
        }
    }
}

function Get-DependenciesFromPackageJson {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $pkg = $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($section in 'dependencies', 'devDependencies') {
        if ($pkg.PSObject.Properties.Name -contains $section -and $null -ne $pkg.$section) {
            foreach ($prop in $pkg.$section.PSObject.Properties) {
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
    param([string]$Path)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $trimmed = $line.Trim()
        # Skip blank lines and comments.
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        # Strip inline comments and environment markers.
        $trimmed = ($trimmed -split '#', 2)[0].Trim()
        $trimmed = ($trimmed -split ';', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        # Split on the first version operator (==, >=, <=, ~=, >, <, =).
        if ($trimmed -match '^(?<name>[A-Za-z0-9._\-]+)\s*(?<op>==|>=|<=|~=|!=|>|<|=)?\s*(?<ver>.*)$') {
            $name = $Matches['name']
            $ver  = ConvertTo-BareVersion $Matches['ver']
            $results.Add([pscustomobject]@{
                Name    = $name
                Version = $ver
            })
        }
    }

    return $results.ToArray()
}

function ConvertTo-BareVersion {
    <#
        Strip leading semver range operators and whitespace, returning a bare
        version string (e.g. '^4.17.21' -> '4.17.21'). Empty/absent -> ''.
    #>
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return '' }
    return ($Version -replace '^[\s\^~>=<!=]+', '').Trim()
}

function Get-LicenseStatus {
    <#
        .SYNOPSIS
            Classify a license against the allow-list and deny-list.
        .DESCRIPTION
            Precedence rules:
              1. A null/empty license is 'unknown'.
              2. A license on the deny-list is 'denied' (deny always wins).
              3. A license on the allow-list is 'approved'.
              4. Anything else is 'unknown'.
            Matching is case-insensitive.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$License,

        [string[]]$AllowList = @(),
        [string[]]$DenyList  = @()
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'unknown' }

    $lic   = $License.Trim()
    $allow = @($AllowList | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $deny  = @($DenyList  | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $key   = $lic.ToLowerInvariant()

    if ($deny  -contains $key) { return 'denied' }
    if ($allow -contains $key) { return 'approved' }
    return 'unknown'
}

function Get-ComplianceConfig {
    <#
        .SYNOPSIS
            Load the allow-list / deny-list policy from a JSON config file.
        .OUTPUTS
            A hashtable with Allow and Deny string arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: '$ConfigPath'"
    }

    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config '$ConfigPath' as JSON: $($_.Exception.Message)"
    }

    $allow = @()
    $deny  = @()
    if ($cfg.PSObject.Properties.Name -contains 'allow' -and $null -ne $cfg.allow) { $allow = @($cfg.allow) }
    if ($cfg.PSObject.Properties.Name -contains 'deny'  -and $null -ne $cfg.deny)  { $deny  = @($cfg.deny) }

    return @{ Allow = $allow; Deny = $deny }
}

function Get-LicenseDatabase {
    <#
        .SYNOPSIS
            Load the local license database (a stand-in for a registry API).
        .OUTPUTS
            A hashtable keyed by "name@version" or "name" -> license string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        throw "License database not found: '$DatabasePath'"
    }

    try {
        $obj = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse license database '$DatabasePath' as JSON: $($_.Exception.Message)"
    }

    $table = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        $table[$prop.Name] = $prop.Value
    }
    return $table
}

function Get-DependencyLicense {
    <#
        .SYNOPSIS
            Look up the license for a dependency. THIS IS THE MOCK SEAM.
        .DESCRIPTION
            In production this resolves the license from the supplied database
            hashtable, trying an exact "name@version" key first and falling
            back to a "name" key. In tests this function is replaced by a
            Pester Mock so no real lookup happens.
            Returns the license string, or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [hashtable]$Database = @{}
    )

    $versionedKey = "$Name@$Version"
    if ($Database.ContainsKey($versionedKey)) { return $Database[$versionedKey] }
    if ($Database.ContainsKey($Name))         { return $Database[$Name] }
    return $null
}

function New-ComplianceReport {
    <#
        .SYNOPSIS
            Build the full compliance report for a manifest.
        .DESCRIPTION
            Orchestrates parsing, license lookup, and classification. Returns
            one object per dependency: Name, Version, License, Status.
        .PARAMETER ManifestPath
            Path to package.json or requirements.txt.
        .PARAMETER ConfigPath
            Path to the allow/deny policy JSON.
        .PARAMETER DatabasePath
            Optional path to the license database JSON used by the default
            Get-DependencyLicense implementation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [string]$DatabasePath
    )

    $config = Get-ComplianceConfig -ConfigPath $ConfigPath
    $deps   = Get-Dependencies -ManifestPath $ManifestPath

    # Load the database only if a path was provided; when the lookup is mocked
    # in tests, no database is needed.
    $database = @{}
    if ($DatabasePath) {
        $database = Get-LicenseDatabase -DatabasePath $DatabasePath
    }

    $report = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in $deps) {
        $license = Get-DependencyLicense -Name $dep.Name -Version $dep.Version -Database $database
        $status  = Get-LicenseStatus -License $license -AllowList $config.Allow -DenyList $config.Deny

        $report.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            # Normalise an absent license to the literal 'unknown' for display.
            License = if ([string]::IsNullOrWhiteSpace($license)) { 'unknown' } else { $license }
            Status  = $status
        })
    }

    return $report.ToArray()
}

function Format-ComplianceReport {
    <#
        .SYNOPSIS
            Render a compliance report as human-readable text with a summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Report
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('Dependency License Compliance Report')
    [void]$sb.AppendLine('====================================')

    # Compute column widths for a tidy table.
    $nameW = 4; $verW = 7; $licW = 7
    foreach ($row in $Report) {
        $nameW = [Math]::Max($nameW, "$($row.Name)".Length)
        $verW  = [Math]::Max($verW,  "$($row.Version)".Length)
        $licW  = [Math]::Max($licW,  "$($row.License)".Length)
    }

    foreach ($row in $Report) {
        $line = '{0}  {1}  {2}  {3}' -f `
            "$($row.Name)".PadRight($nameW),
            "$($row.Version)".PadRight($verW),
            "$($row.License)".PadRight($licW),
            $row.Status
        [void]$sb.AppendLine($line)
    }

    $approved = @($Report | Where-Object Status -eq 'approved').Count
    $denied   = @($Report | Where-Object Status -eq 'denied').Count
    $unknown  = @($Report | Where-Object Status -eq 'unknown').Count

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Summary: $approved approved, $denied denied, $unknown unknown")

    return $sb.ToString()
}

Export-ModuleMember -Function `
    Get-Dependencies, ConvertTo-BareVersion, Get-LicenseStatus, `
    Get-ComplianceConfig, Get-LicenseDatabase, Get-DependencyLicense, `
    New-ComplianceReport, Format-ComplianceReport
