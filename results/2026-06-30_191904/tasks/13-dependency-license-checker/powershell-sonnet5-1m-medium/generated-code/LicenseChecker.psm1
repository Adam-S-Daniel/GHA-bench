#requires -Version 7.0
<#
    LicenseChecker.psm1

    Parses dependency manifests (package.json / requirements.txt), resolves each
    dependency's license, checks it against an allow-list / deny-list, and
    produces a compliance report.

    Design notes:
      - Resolve-PackageLicense is the "real" network lookup (npm registry /
        PyPI). It is the seam Pester tests mock via `Mock Resolve-PackageLicense`.
      - Get-PackageLicense wraps it: if a local -LicenseDatabase hashtable is
        supplied (used for offline/CI runs), it is consulted first so no
        external service is required in the pipeline.
#>

Set-StrictMode -Version Latest

function Get-DependencyManifest {
    <#
        Parses a dependency manifest file and returns an array of dependency
        objects with Name and Version. Supports package.json (dependencies +
        devDependencies) and requirements.txt (pip freeze / requirements format).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest file not found: '$Path'"
    }

    $fileName = Split-Path -Path $Path -Leaf
    $extension = [System.IO.Path]::GetExtension($fileName).ToLowerInvariant()
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Format is detected by extension rather than an exact filename match so
    # that renamed copies of a manifest (e.g. a fixture swapped in as
    # manifest.json) are still parsed correctly.
    if ($extension -eq '.json') {
        $json = $null
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON manifest at '$Path': $($_.Exception.Message)"
        }

        foreach ($section in @('dependencies', 'devDependencies')) {
            if ($json.PSObject.Properties.Name -contains $section) {
                $deps = $json.$section
                foreach ($prop in $deps.PSObject.Properties) {
                    $rawVersion = $prop.Value
                    $version = $rawVersion -replace '^[\^~>=<\s]+', ''
                    $results.Add([PSCustomObject]@{
                        Name    = $prop.Name
                        Version = $version
                    })
                }
            }
        }
    }
    elseif ($extension -eq '.txt') {
        $lines = Get-Content -LiteralPath $Path
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
                continue
            }

            if ($trimmed -match '^([A-Za-z0-9_.\-]+)\s*(==|>=|<=|~=|!=|>|<)\s*([A-Za-z0-9.\-_]+)') {
                $results.Add([PSCustomObject]@{
                    Name    = $Matches[1]
                    Version = $Matches[3]
                })
            }
            elseif ($trimmed -match '^([A-Za-z0-9_.\-]+)$') {
                $results.Add([PSCustomObject]@{
                    Name    = $Matches[1]
                    Version = 'unknown'
                })
            }
        }
    }
    else {
        throw "Unsupported manifest format for file '$fileName'. Supported formats: package.json (.json), requirements.txt (.txt)"
    }

    return $results.ToArray()
}

function Resolve-PackageLicense {
    <#
        Performs the "real" license lookup against a public package registry.
        This is the network seam: Pester unit tests replace it with
        `Mock Resolve-PackageLicense` so tests never touch the network.
        Not invoked directly by the CI workflow (see Get-PackageLicense).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [ValidateSet('npm', 'pypi')]
        [string]$Registry = 'npm'
    )

    try {
        if ($Registry -eq 'npm') {
            $uri = "https://registry.npmjs.org/$Name"
            $meta = Invoke-RestMethod -Uri $uri -TimeoutSec 10
            return $meta.license
        }
        else {
            $uri = "https://pypi.org/pypi/$Name/json"
            $meta = Invoke-RestMethod -Uri $uri -TimeoutSec 10
            return $meta.info.license
        }
    }
    catch {
        Write-Warning "License lookup failed for '$Name': $($_.Exception.Message)"
        return $null
    }
}

function Get-PackageLicense {
    <#
        Returns the license string for a given package. Prefers a local
        -LicenseDatabase (name -> license hashtable/PSCustomObject) so the
        pipeline can run entirely offline; falls back to Resolve-PackageLicense
        (network) only when no local database is supplied.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        $LicenseDatabase
    )

    if ($null -ne $LicenseDatabase) {
        if ($LicenseDatabase -is [System.Collections.IDictionary]) {
            if ($LicenseDatabase.Contains($Name)) {
                return $LicenseDatabase[$Name]
            }
        }
        else {
            if ($LicenseDatabase.PSObject.Properties.Name -contains $Name) {
                return $LicenseDatabase.$Name
            }
        }
        return $null
    }

    return Resolve-PackageLicense -Name $Name -Version $Version
}

function Test-LicenseStatus {
    <#
        Classifies a license string against allow/deny lists.
        Returns one of: 'Approved', 'Denied', 'Unknown'.
        Deny takes precedence over allow when a license appears in both lists.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$License,

        [Parameter(Mandatory)]
        [string[]]$AllowList,

        [Parameter(Mandatory)]
        [string[]]$DenyList
    )

    if ([string]::IsNullOrWhiteSpace($License)) {
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

function New-ComplianceReport {
    <#
        Orchestrates the full check: parses the manifest, resolves each
        dependency's license, classifies it against the config's allow/deny
        lists, and returns an array of report row objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        $Config,

        [Parameter()]
        $LicenseDatabase
    )

    $configProps = $Config.PSObject.Properties.Name
    if (-not ($configProps -contains 'allow') -or -not ($configProps -contains 'deny')) {
        throw "Config must contain 'allow' and 'deny' arrays."
    }

    $dependencies = Get-DependencyManifest -Path $ManifestPath
    $report = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($dep in $dependencies) {
        $license = Get-PackageLicense -Name $dep.Name -Version $dep.Version -LicenseDatabase $LicenseDatabase
        $status = Test-LicenseStatus -License $license -AllowList $Config.allow -DenyList $Config.deny

        $report.Add([PSCustomObject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = if ($license) { $license } else { 'Unknown' }
            Status  = $status
        })
    }

    return $report.ToArray()
}

function Format-ComplianceReport {
    <#
        Renders a compliance report (array of Name/Version/License/Status
        objects) as a markdown table, suitable for GITHUB_STEP_SUMMARY.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Report
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('| Package | Version | License | Status |')
    $lines.Add('|---------|---------|---------|--------|')

    foreach ($row in $Report) {
        $lines.Add("| $($row.Name) | $($row.Version) | $($row.License) | $($row.Status) |")
    }

    return ($lines -join "`n")
}

Export-ModuleMember -Function Get-DependencyManifest, Resolve-PackageLicense, Get-PackageLicense, Test-LicenseStatus, New-ComplianceReport, Format-ComplianceReport
