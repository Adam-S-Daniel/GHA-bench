# LicenseChecker.psm1
# Dependency license compliance checker: parses a manifest, looks up each
# dependency's license, and compares it against an allow/deny config.

function Get-DependenciesFromManifest {
    <#
        .SYNOPSIS
        Parses a dependency manifest (package.json or requirements.txt) and
        returns the list of dependency names/versions it declares.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest file not found: $Path"
    }

    $fileName = Split-Path -Path $Path -Leaf
    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($fileName -eq 'package.json') {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

        foreach ($section in @('dependencies', 'devDependencies')) {
            if ($json.PSObject.Properties.Name -contains $section) {
                foreach ($prop in $json.$section.PSObject.Properties) {
                    $results.Add([pscustomobject]@{
                        Name    = $prop.Name
                        Version = ($prop.Value -replace '^[\^~>=<\s]+', '')
                    })
                }
            }
        }
    }
    elseif ($fileName -match '(^|\/)requirements.*\.txt$') {
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
        throw "Unsupported manifest type: $Path. Expected package.json or requirements.txt."
    }

    return $results
}

# In-memory override table used to mock the license source in tests, so
# no real registry/network call is ever needed to exercise the logic.
$script:LicenseSourceOverrides = @{}

function Set-MockPackageLicense {
    <#
        .SYNOPSIS
        Test helper: registers a fake license result for a given
        package name/version, so Get-PackageLicense returns it instead
        of calling out to a real license registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$License
    )
    $script:LicenseSourceOverrides["$Name@$Version"] = $License
}

function Clear-MockPackageLicense {
    <#
        .SYNOPSIS
        Test helper: clears all registered mock license results.
    #>
    [CmdletBinding()]
    param()
    $script:LicenseSourceOverrides = @{}
}

function Get-PackageLicense {
    <#
        .SYNOPSIS
        Looks up the license for a package name/version. In production
        this would query a package registry; that call is mocked in
        tests via Set-MockPackageLicense so tests never hit the network.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version
    )

    $key = "$Name@$Version"
    if ($script:LicenseSourceOverrides.ContainsKey($key)) {
        return $script:LicenseSourceOverrides[$key]
    }

    return 'UNKNOWN'
}

function Test-LicenseCompliance {
    <#
        .SYNOPSIS
        Classifies a license string against an allow-list and a
        deny-list, returning 'Approved', 'Denied', or 'Unknown'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$License,
        [Parameter(Mandatory)][string[]]$AllowList,
        [Parameter(Mandatory)][string[]]$DenyList
    )

    if ($License -eq 'UNKNOWN') {
        return 'Unknown'
    }
    if ($DenyList -icontains $License) {
        return 'Denied'
    }
    if ($AllowList -icontains $License) {
        return 'Approved'
    }
    return 'Unknown'
}

function Get-LicensePolicy {
    <#
        .SYNOPSIS
        Loads an allow-list/deny-list license policy from a JSON config
        file, e.g. { "allowList": [...], "denyList": [...] }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "License policy file not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    return [pscustomobject]@{
        AllowList = @($json.allowList)
        DenyList  = @($json.denyList)
    }
}

function New-ComplianceReport {
    <#
        .SYNOPSIS
        Builds a compliance report: for each dependency, resolves its
        license and classifies it against the given policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Dependencies,
        [Parameter(Mandatory)][pscustomobject]$Policy
    )

    $report = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($dep in $Dependencies) {
        $license = Get-PackageLicense -Name $dep.Name -Version $dep.Version
        $status = Test-LicenseCompliance -License $license -AllowList $Policy.AllowList -DenyList $Policy.DenyList

        $report.Add([pscustomobject]@{
            Name    = $dep.Name
            Version = $dep.Version
            License = $license
            Status  = $status
        })
    }

    return $report
}

Export-ModuleMember -Function Get-DependenciesFromManifest, Get-PackageLicense, `
    Set-MockPackageLicense, Clear-MockPackageLicense, Test-LicenseCompliance, `
    Get-LicensePolicy, New-ComplianceReport
