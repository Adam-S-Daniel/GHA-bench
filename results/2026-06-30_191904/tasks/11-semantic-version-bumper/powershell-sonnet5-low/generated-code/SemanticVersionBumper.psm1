#
# SemanticVersionBumper.psm1
#
# Parses a version file (VERSION text file or package.json), inspects conventional
# commit messages to decide the next semantic version, updates the version file,
# and generates a changelog entry.
#
# Conventional commit rules applied (highest impact wins):
#   - "BREAKING CHANGE" in the message, or a "!" before the ":" (e.g. feat!:) -> major
#   - "feat:" prefix                                                          -> minor
#   - "fix:" prefix                                                           -> patch
#   - anything else (chore, docs, refactor, test, ...)                        -> no bump

$SemVerPattern = '^\d+\.\d+\.\d+$'

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file.
    .DESCRIPTION
        Supports two formats: a package.json file with a "version" field, or a
        plain text file whose entire (trimmed) contents are the version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: $Path"
    }

    $isPackageJson = [System.IO.Path]::GetExtension($Path) -eq '.json'
    $raw = Get-Content -Path $Path -Raw

    if ($isPackageJson) {
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to parse package.json at '$Path': $($_.Exception.Message)"
        }
        if (-not $json.PSObject.Properties.Match('version') -or [string]::IsNullOrWhiteSpace($json.version)) {
            throw "package.json at '$Path' does not contain a 'version' field."
        }
        $version = $json.version
    }
    else {
        $version = $raw.Trim()
    }

    if ($version -notmatch $SemVerPattern) {
        throw "Value '$version' found in '$Path' is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }

    return $version
}

function Get-VersionBumpType {
    <#
    .SYNOPSIS
        Determines the semantic version bump type from a list of conventional commit messages.
    .OUTPUTS
        One of: 'major', 'minor', 'patch', 'none'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Commits
    )

    if (-not $Commits -or $Commits.Count -eq 0) {
        throw "No commit messages were supplied; cannot determine a version bump."
    }

    $bump = 'none'
    foreach ($commit in $Commits) {
        if ($commit -match 'BREAKING CHANGE' -or $commit -match '^[a-zA-Z]+(\([^)]*\))?!:') {
            return 'major'
        }
        elseif ($commit -match '^feat(\([^)]*\))?:') {
            $bump = 'minor'
        }
        elseif ($commit -match '^fix(\([^)]*\))?:' -and $bump -ne 'minor') {
            $bump = 'patch'
        }
    }

    return $bump
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version given a current version and a bump type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [string]$BumpType
    )

    if ($CurrentVersion -notmatch $SemVerPattern) {
        throw "Current version '$CurrentVersion' is not a valid semantic version."
    }

    if ($BumpType -notin @('major', 'minor', 'patch', 'none')) {
        throw "Unsupported bump type: '$BumpType'. Expected one of major, minor, patch, none."
    }

    $parts = $CurrentVersion.Split('.') | ForEach-Object { [int]$_ }
    $major, $minor, $patch = $parts[0], $parts[1], $parts[2]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { }
        default { throw "Unsupported bump type: '$BumpType'" }
    }

    return "$major.$minor.$patch"
}

function Set-Version {
    <#
    .SYNOPSIS
        Writes a new semantic version into a version file (package.json or plain text).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: $Path"
    }

    $isPackageJson = [System.IO.Path]::GetExtension($Path) -eq '.json'

    if ($isPackageJson) {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $json.version = $NewVersion
        ($json | ConvertTo-Json -Depth 10) | Set-Content -Path $Path
    }
    else {
        Set-Content -Path $Path -Value $NewVersion
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Builds a Markdown changelog section grouping commits by conventional type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string[]]$Commits,

        [Parameter(Mandatory)]
        [string]$Date
    )

    $groups = [ordered]@{
        'Breaking Changes' = [System.Collections.Generic.List[string]]::new()
        'Features'         = [System.Collections.Generic.List[string]]::new()
        'Bug Fixes'        = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($commit in $Commits) {
        if ($commit -match 'BREAKING CHANGE:\s*(.+)$') {
            $groups['Breaking Changes'].Add($matches[1].Trim())
        }
        elseif ($commit -match '^feat(\([^)]*\))?!?:\s*(.+)$') {
            $groups['Features'].Add($matches[2].Trim())
        }
        elseif ($commit -match '^fix(\([^)]*\))?!?:\s*(.+)$') {
            $groups['Bug Fixes'].Add($matches[2].Trim())
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")
    $lines.Add('')

    foreach ($key in $groups.Keys) {
        if ($groups[$key].Count -gt 0) {
            $lines.Add("### $key")
            foreach ($item in $groups[$key]) {
                $lines.Add("- $item")
            }
            $lines.Add('')
        }
    }

    return ($lines -join "`n")
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        End-to-end orchestration: reads current version, reads commit log, determines
        bump type, computes next version, updates the version file, and writes a
        changelog entry.
    .OUTPUTS
        A hashtable with PreviousVersion, NewVersion, BumpType and ChangelogEntry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionFilePath,

        [Parameter(Mandatory)]
        [string]$CommitLogPath,

        [Parameter(Mandatory)]
        [string]$ChangelogPath,

        [Parameter()]
        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    if (-not (Test-Path -Path $CommitLogPath -PathType Leaf)) {
        throw "Commit log file not found: $CommitLogPath"
    }

    $previousVersion = Get-CurrentVersion -Path $VersionFilePath

    $commits = Get-Content -Path $CommitLogPath | Where-Object { $_.Trim().Length -gt 0 }
    if (-not $commits -or $commits.Count -eq 0) {
        throw "Commit log file '$CommitLogPath' contains no commit messages."
    }

    $bumpType = Get-VersionBumpType -Commits $commits
    $newVersion = Get-NextVersion -CurrentVersion $previousVersion -BumpType $bumpType

    Set-Version -Path $VersionFilePath -NewVersion $newVersion

    $changelogEntry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date
    $existing = ''
    if (Test-Path -Path $ChangelogPath -PathType Leaf) {
        $existing = Get-Content -Path $ChangelogPath -Raw
    }
    Set-Content -Path $ChangelogPath -Value ($changelogEntry + "`n" + $existing)

    return [pscustomobject]@{
        PreviousVersion = $previousVersion
        NewVersion      = $newVersion
        BumpType        = $bumpType
        ChangelogEntry  = $changelogEntry
    }
}

Export-ModuleMember -Function Get-CurrentVersion, Get-VersionBumpType, Get-NextVersion, Set-Version, New-ChangelogEntry, Invoke-VersionBump
