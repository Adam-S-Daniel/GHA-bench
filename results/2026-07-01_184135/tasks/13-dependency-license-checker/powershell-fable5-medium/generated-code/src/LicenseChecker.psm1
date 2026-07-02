<#
.SYNOPSIS
    Dependency license compliance checker.

.DESCRIPTION
    Grown via red/green TDD against tests/LicenseChecker.Tests.ps1.

    Approach:
      1. Get-DependencyList     - parse a manifest (package.json or
                                  requirements.txt) into (Name, Version) records.
      2. Get-DependencyLicense  - look up a package's license. In production
                                  this would call a registry/API; here it reads
                                  a JSON "license database" file so it is fully
                                  deterministic and trivially mockable (Pester
                                  mocks it directly in report-level tests).
      3. Get-LicenseStatus      - classify a license as Approved / Denied /
                                  Unknown against configured allow/deny lists.
                                  Deny wins over allow; anything unlisted or
                                  unresolvable is Unknown.
      4. New-ComplianceReport   - orchestrates 1-3 into a report object.
      5. Format-ComplianceReport- renders stable, machine-parseable lines
                                  (RESULT|name|version|license|status) used by
                                  the CI pipeline assertions.
#>

Set-StrictMode -Version Latest

function Get-DependencyList {
    <#
    .SYNOPSIS
        Parses a dependency manifest into records with Name and Version.
    .PARAMETER ManifestPath
        Path to package.json or requirements.txt (detected by file name).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest file not found: '$ManifestPath'. Provide a path to an existing package.json or requirements.txt."
    }

    $fileName = [IO.Path]::GetFileName($ManifestPath)
    switch -Wildcard ($fileName) {
        'package.json'      { return ConvertFrom-PackageJsonManifest -Path $ManifestPath }
        '*package.json'     { return ConvertFrom-PackageJsonManifest -Path $ManifestPath }
        'requirements*.txt' { return ConvertFrom-RequirementsManifest -Path $ManifestPath }
        default {
            throw "Unsupported manifest type: '$fileName'. Supported manifests: package.json, requirements*.txt."
        }
    }
}

function ConvertFrom-PackageJsonManifest {
    # Internal: parse an npm package.json (dependencies + devDependencies).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $json = $raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Manifest '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    $deps = [System.Collections.Generic.List[object]]::new()
    foreach ($section in 'dependencies', 'devDependencies') {
        if ($json -is [hashtable] -and $json.ContainsKey($section) -and $json[$section] -is [hashtable]) {
            foreach ($name in $json[$section].Keys) {
                # Strip semver range operators so "^2.0.0" reports as "2.0.0".
                $version = ([string]$json[$section][$name]) -replace '^[\^~>=<\s]+', ''
                $deps.Add([pscustomobject]@{ Name = $name; Version = $version })
            }
        }
    }
    return $deps
}

function ConvertFrom-RequirementsManifest {
    # Internal: parse a pip requirements.txt (comments/blank lines ignored).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $deps = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }

        # name, optional comparison operator, optional version
        if ($trimmed -match '^(?<name>[A-Za-z0-9._\-]+)\s*(?:(?:==|>=|<=|~=|!=|>|<)\s*(?<version>[^,;#\s]+))?') {
            $version = if ($Matches.ContainsKey('version') -and $Matches['version']) { $Matches['version'] } else { 'unspecified' }
            $deps.Add([pscustomobject]@{ Name = $Matches['name']; Version = $version })
        }
        else {
            Write-Warning "Skipping unparseable requirements line: '$trimmed'"
        }
    }
    return $deps
}

function Get-DependencyLicense {
    <#
    .SYNOPSIS
        Looks up the license for a package name.
    .DESCRIPTION
        Reads a JSON file mapping package name -> SPDX license id. This stands
        in for a real registry lookup so tests and CI are offline and
        deterministic; Pester tests also Mock this function directly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        # Not [Mandatory]: report-level tests Mock this function and call it
        # without a database path, and Pester mocks re-bind real parameters.
        [string]$LicenseDatabasePath
    )

    if ([string]::IsNullOrWhiteSpace($LicenseDatabasePath) -or
        -not (Test-Path -LiteralPath $LicenseDatabasePath -PathType Leaf)) {
        throw "License database not found: '$LicenseDatabasePath'."
    }

    try {
        $db = Get-Content -LiteralPath $LicenseDatabasePath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "License database '$LicenseDatabasePath' is not valid JSON: $($_.Exception.Message)"
    }

    if ($db -is [hashtable] -and $db.ContainsKey($Name)) { return [string]$db[$Name] }
    return $null
}

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Classifies a license against allow/deny lists.
    .DESCRIPTION
        Deny list takes precedence over allow list; empty/unlisted licenses
        are Unknown. Comparison is case-insensitive (PowerShell -contains).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$License,

        [string[]]$AllowList = @(),
        [string[]]$DenyList  = @()
    )

    if ([string]::IsNullOrWhiteSpace($License)) { return 'Unknown' }
    if ($DenyList  -contains $License) { return 'Denied' }
    if ($AllowList -contains $License) { return 'Approved' }
    return 'Unknown'
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Builds a compliance report for every dependency in a manifest.
    .PARAMETER ConfigPath
        JSON config with "allowList" and "denyList" arrays of license ids.
    .PARAMETER LicenseDatabasePath
        Optional JSON license database passed through to Get-DependencyLicense.
        Tests that Mock Get-DependencyLicense can omit it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [string]$LicenseDatabasePath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: '$ConfigPath'."
    }
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        throw "Config file '$ConfigPath' is not valid JSON: $($_.Exception.Message)"
    }
    $allow = @($config['allowList'])
    $deny  = @($config['denyList'])

    $lookupArgs = @{}
    if ($LicenseDatabasePath) { $lookupArgs['LicenseDatabasePath'] = $LicenseDatabasePath }

    $entries = foreach ($dep in (Get-DependencyList -ManifestPath $ManifestPath | Sort-Object Name)) {
        $license = Get-DependencyLicense -Name $dep.Name @lookupArgs
        [pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            # Surface unresolvable licenses explicitly rather than as blanks.
            License = if ([string]::IsNullOrWhiteSpace($license)) { 'UNKNOWN' } else { $license }
            Status  = Get-LicenseStatus -License $license -AllowList $allow -DenyList $deny
        }
    }
    $entries = @($entries)

    [pscustomobject]@{
        Manifest = [IO.Path]::GetFileName($ManifestPath)
        Entries  = $entries
        Summary  = [pscustomobject]@{
            Approved = @($entries | Where-Object Status -eq 'Approved').Count
            Denied   = @($entries | Where-Object Status -eq 'Denied').Count
            Unknown  = @($entries | Where-Object Status -eq 'Unknown').Count
            Total    = $entries.Count
        }
    }
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Renders a report as stable pipe-delimited lines for logs/CI parsing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("MANIFEST|$($Report.Manifest)")
    foreach ($e in $Report.Entries) {
        $lines.Add("RESULT|$($e.Name)|$($e.Version)|$($e.License)|$($e.Status)")
    }
    $s = $Report.Summary
    $lines.Add("SUMMARY|Approved=$($s.Approved)|Denied=$($s.Denied)|Unknown=$($s.Unknown)|Total=$($s.Total)")
    return $lines
}

Export-ModuleMember -Function Get-DependencyList, Get-DependencyLicense, Get-LicenseStatus, New-ComplianceReport, Format-ComplianceReport
