<#
    LicenseChecker.psm1

    Core logic for the dependency license compliance checker:
      - Get-ManifestDependency   parses package.json / requirements.txt
      - Get-PackageLicense       looks up a package's license (mocked in tests)
      - Resolve-LicenseStatus    classifies a license as Approved/Denied/Unknown
      - New-LicenseComplianceReport   ties the above together into a report
#>

function Get-ManifestDependency {
    <#
        .SYNOPSIS
        Parses a dependency manifest and returns one object per dependency
        with Name and Version properties.

        .DESCRIPTION
        Supports npm-style package.json ("dependencies" + "devDependencies")
        and pip-style requirements.txt files. The format is chosen by file
        extension/name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest file not found: $Path"
    }

    $fileName = Split-Path -Path $Path -Leaf

    if ($fileName -eq 'requirements.txt' -or $fileName -like '*.txt') {
        return Get-RequirementsTxtDependency -Path $Path
    }
    elseif ($fileName -eq 'package.json' -or $fileName -like '*.json') {
        return Get-PackageJsonDependency -Path $Path
    }
    else {
        throw "Unsupported manifest format for file: $fileName"
    }
}

function Get-PackageJsonDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse package.json at '$Path': $($_.Exception.Message)"
    }

    $dependencies = [System.Collections.Generic.List[object]]::new()

    foreach ($section in @('dependencies', 'devDependencies')) {
        $sectionValue = $json.$section
        if ($null -eq $sectionValue) { continue }

        foreach ($property in $sectionValue.PSObject.Properties) {
            $dependencies.Add([PSCustomObject]@{
                Name    = $property.Name
                Version = ($property.Value -replace '^[\^~>=<]+', '')
            })
        }
    }

    return $dependencies
}

function Get-RequirementsTxtDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $dependencies = [System.Collections.Generic.List[object]]::new()

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed -match '^(?<name>[A-Za-z0-9_.\-]+)\s*(==|>=|<=|~=)\s*(?<version>[A-Za-z0-9_.\-]+)') {
            $dependencies.Add([PSCustomObject]@{
                Name    = $Matches.name
                Version = $Matches.version
            })
        }
        else {
            $dependencies.Add([PSCustomObject]@{
                Name    = $trimmed
                Version = 'unspecified'
            })
        }
    }

    return $dependencies
}

function Get-PackageLicense {
    <#
        .SYNOPSIS
        Looks up the license for a named package from a local license
        database file. Real production use would point this at an
        internal license index; tests mock this function so no real
        file or network I/O is needed to exercise the rest of the
        module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$LicenseDatabasePath
    )

    if (-not (Test-Path -LiteralPath $LicenseDatabasePath -PathType Leaf)) {
        throw "License database file not found: $LicenseDatabasePath"
    }

    try {
        $db = Get-Content -LiteralPath $LicenseDatabasePath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse license database at '$LicenseDatabasePath': $($_.Exception.Message)"
    }

    $property = $db.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Resolve-LicenseStatus {
    <#
        .SYNOPSIS
        Classifies a license string as Approved, Denied, or Unknown given
        an allow-list and deny-list. Deny takes precedence over allow as a
        fail-safe if a license somehow appears on both lists.
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

function New-LicenseComplianceReport {
    <#
        .SYNOPSIS
        Builds a full compliance report for every dependency in a manifest.

        .OUTPUTS
        PSCustomObject with:
          Dependencies - array of {Name, Version, License, Status}
          Summary      - {Approved, Denied, Unknown, Total}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$PolicyPath,

        [Parameter(Mandatory)]
        [string]$LicenseDatabasePath
    )

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "Policy file not found: $PolicyPath"
    }

    try {
        $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse policy file at '$PolicyPath': $($_.Exception.Message)"
    }

    $allowList = @($policy.AllowList)
    $denyList = @($policy.DenyList)

    $dependencies = Get-ManifestDependency -Path $ManifestPath

    $rows = foreach ($dependency in $dependencies) {
        $license = Get-PackageLicense -Name $dependency.Name -LicenseDatabasePath $LicenseDatabasePath
        $status = Resolve-LicenseStatus -License $license -AllowList $allowList -DenyList $denyList

        [PSCustomObject]@{
            Name    = $dependency.Name
            Version = $dependency.Version
            License = $license
            Status  = $status
        }
    }
    $rows = @($rows)

    $summary = [PSCustomObject]@{
        Approved = @($rows | Where-Object Status -eq 'Approved').Count
        Denied   = @($rows | Where-Object Status -eq 'Denied').Count
        Unknown  = @($rows | Where-Object Status -eq 'Unknown').Count
        Total    = $rows.Count
    }

    return [PSCustomObject]@{
        Dependencies = $rows
        Summary      = $summary
    }
}

Export-ModuleMember -Function Get-ManifestDependency, Get-PackageLicense, Resolve-LicenseStatus, New-LicenseComplianceReport
