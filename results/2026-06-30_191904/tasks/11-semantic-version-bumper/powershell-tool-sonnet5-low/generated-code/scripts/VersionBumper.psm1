# VersionBumper.psm1
# Semantic version bumper driven by conventional commit messages.
# Supports plain VERSION text files and package.json files.

$script:SemVerPattern = '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$'

function Get-CurrentVersion {
    <#
        Reads the current semantic version from a version file.
        Supports two formats:
          - a plain text file containing just the version string
          - a package.json file with a top-level "version" field
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Version file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw

    if ($Path -match '\.json$') {
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            throw "Unable to parse '$Path' as JSON: $($_.Exception.Message)"
        }
        if (-not $json.version) {
            throw "Unable to parse a version field from JSON file: $Path"
        }
        $version = $json.version
    } else {
        $version = $raw.Trim()
    }

    if ($version -notmatch $script:SemVerPattern) {
        throw "Unable to parse a valid semantic version from: $Path"
    }

    return $version
}

function Get-VersionBumpType {
    <#
        Inspects an array of conventional commit message lines and determines
        the highest-impact bump type: major, minor, patch, or none.

        Rules:
          - a "BREAKING CHANGE:" footer, or a "!" before the colon in the
            subject line (e.g. "feat(config)!: ...") -> major
          - a "feat" prefix -> minor
          - a "fix" prefix -> patch
          - anything else -> no impact
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$CommitMessages = @()
    )

    $hasMajor = $false
    $hasMinor = $false
    $hasPatch = $false

    foreach ($line in $CommitMessages) {
        if ($line -match '^BREAKING CHANGE:') {
            $hasMajor = $true
        }
        if ($line -match '^\w+(\([^)]*\))?!:') {
            $hasMajor = $true
        }
        if ($line -match '^feat(\([^)]*\))?:') {
            $hasMinor = $true
        }
        if ($line -match '^fix(\([^)]*\))?:') {
            $hasPatch = $true
        }
    }

    if ($hasMajor) { return 'major' }
    if ($hasMinor) { return 'minor' }
    if ($hasPatch) { return 'patch' }
    return 'none'
}

function Get-NextVersion {
    <#
        Computes the next semantic version given a current version and a bump
        type ('major', 'minor', 'patch', or 'none').
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    if ($CurrentVersion -notmatch $script:SemVerPattern) {
        throw "Invalid semantic version: $CurrentVersion"
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    $patch = [int]$Matches.patch

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { }
    }

    return "$major.$minor.$patch"
}

function Update-VersionFile {
    <#
        Writes the new version back into a version file, preserving the
        surrounding structure (all other package.json fields are untouched).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if ($Path -match '\.json$') {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $json.version = $NewVersion
        ($json | ConvertTo-Json -Depth 20) | Set-Content -Path $Path -NoNewline
    } else {
        Set-Content -Path $Path -Value $NewVersion -NoNewline
    }
}

function New-ChangelogEntry {
    <#
        Builds a markdown changelog entry for the given version, grouping
        conventional commits into Breaking Changes / Features / Fixes / Other.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [AllowEmptyCollection()]
        [string[]]$CommitMessages = @()
    )

    $breaking = @()
    $features = @()
    $fixes = @()

    foreach ($line in $CommitMessages) {
        if ($line -match '^BREAKING CHANGE:\s*(.*)') {
            $breaking += $Matches[1]
        } elseif ($line -match '^feat(\([^)]*\))?!?:\s*(.*)') {
            $features += $Matches[2]
            if ($line -match '!:') { $breaking += $Matches[2] }
        } elseif ($line -match '^fix(\([^)]*\))?!?:\s*(.*)') {
            $fixes += $Matches[2]
            if ($line -match '!:') { $breaking += $Matches[2] }
        }
    }

    $lines = @("## $Version", '')

    if ($breaking.Count -gt 0) {
        $lines += '### Breaking Changes'
        foreach ($item in $breaking) { $lines += "- $item" }
        $lines += ''
    }
    if ($features.Count -gt 0) {
        $lines += '### Features'
        foreach ($item in $features) { $lines += "- $item" }
        $lines += ''
    }
    if ($fixes.Count -gt 0) {
        $lines += '### Fixes'
        foreach ($item in $fixes) { $lines += "- $item" }
        $lines += ''
    }

    return ($lines -join "`n")
}

function Invoke-VersionBump {
    <#
        End-to-end orchestration: reads the current version, determines the
        bump type from commit messages, computes and writes the new version,
        and prepends a changelog entry. Returns an object describing the
        result.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$VersionFilePath,

        [Parameter(Mandatory)]
        [string]$ChangelogPath,

        [AllowEmptyCollection()]
        [string[]]$CommitMessages = @()
    )

    $currentVersion = Get-CurrentVersion -Path $VersionFilePath
    $bumpType = Get-VersionBumpType -CommitMessages $CommitMessages
    $newVersion = Get-NextVersion -CurrentVersion $currentVersion -BumpType $bumpType

    Update-VersionFile -Path $VersionFilePath -NewVersion $newVersion

    $entry = New-ChangelogEntry -Version $newVersion -CommitMessages $CommitMessages
    $existing = ''
    if (Test-Path -Path $ChangelogPath) {
        $existing = Get-Content -Path $ChangelogPath -Raw
    }
    Set-Content -Path $ChangelogPath -Value ($entry + "`n" + $existing)

    return [PSCustomObject]@{
        PreviousVersion = $currentVersion
        NewVersion      = $newVersion
        BumpType        = $bumpType
        ChangelogEntry  = $entry
    }
}

Export-ModuleMember -Function Get-CurrentVersion, Get-VersionBumpType, Get-NextVersion, Update-VersionFile, New-ChangelogEntry, Invoke-VersionBump
