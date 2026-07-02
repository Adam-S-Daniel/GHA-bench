# VersionBumper.psm1
# Semantic version bumper driven by conventional commit messages.
#
# Bump rules (highest wins across all commits):
#   breaking change (BREAKING CHANGE footer or "type!:" bang) -> major
#   feat  -> minor
#   fix   -> patch
#   anything else -> none

Set-StrictMode -Version Latest

function Get-BumpType {
    <#
    .SYNOPSIS
        Determines the semantic version bump type from conventional commit messages.
    .PARAMETER Commits
        One or more commit messages (subject, optionally with body).
    .OUTPUTS
        'major', 'minor', 'patch', or 'none'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits
    )

    $bump = 'none'
    # Rank lets us keep only the highest bump seen so far.
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }

    foreach ($commit in $Commits) {
        $candidate = 'none'
        # Breaking: "BREAKING CHANGE"/"BREAKING-CHANGE" anywhere, or a "!"
        # immediately before the colon in the subject (e.g. "feat!:", "fix(api)!:").
        if ($commit -match 'BREAKING[ -]CHANGE' -or $commit -match '^\s*\w+(\([^)]*\))?!:') {
            $candidate = 'major'
        }
        elseif ($commit -match '^\s*feat(\([^)]*\))?:') {
            $candidate = 'minor'
        }
        elseif ($commit -match '^\s*fix(\([^)]*\))?:') {
            $candidate = 'patch'
        }

        if ($rank[$candidate] -gt $rank[$bump]) { $bump = $candidate }
    }

    return $bump
}

function Step-Version {
    <#
    .SYNOPSIS
        Applies a bump type to a semantic version string.
    .PARAMETER Version
        Current version in MAJOR.MINOR.PATCH form.
    .PARAMETER BumpType
        One of major / minor / patch / none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "'$Version' is not a valid semantic version (expected MAJOR.MINOR.PATCH, e.g. 1.2.3)."
    }
    $major, $minor, $patch = [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]

    switch ($BumpType) {
        'major' { return "$($major + 1).0.0" }
        'minor' { return "$major.$($minor + 1).0" }
        'patch' { return "$major.$minor.$($patch + 1)" }
        'none'  { return $Version }
    }
}

function Test-SemVer {
    # Internal helper: validates MAJOR.MINOR.PATCH, throws with context on failure.
    param([string]$Version, [string]$Source)
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "'$Version' (from $Source) is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }
}

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file or package.json.
    .PARAMETER Path
        Path to the version file. Files named package.json are parsed as JSON
        and the "version" property is used; any other file is treated as a
        plain text file containing the version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'. Provide a plain version file or a package.json."
    }

    $raw = Get-Content -Path $Path -Raw
    if ((Split-Path -Leaf $Path) -eq 'package.json') {
        try {
            $json = $raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
        }
        if (-not ($json.PSObject.Properties.Name -contains 'version')) {
            throw "'$Path' has no `"version`" property."
        }
        $version = [string]$json.version
    }
    else {
        $version = $raw.Trim()
    }

    Test-SemVer -Version $version -Source $Path
    return $version
}

function Set-CurrentVersion {
    <#
    .SYNOPSIS
        Writes a new version to a version file or package.json (in place).
        For package.json only the "version" property is replaced; all other
        fields are preserved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Version
    )

    Test-SemVer -Version $Version -Source 'Set-CurrentVersion input'
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'. Cannot update a file that does not exist."
    }

    if ((Split-Path -Leaf $Path) -eq 'package.json') {
        # Targeted regex replace on the "version" property keeps the original
        # formatting/field order intact (a JSON round-trip would reformat).
        $raw = Get-Content -Path $Path -Raw
        $rx = [regex]'("version"\s*:\s*")[^"]*(")'
        $updated = $rx.Replace($raw, "`${1}$Version`${2}", 1) # first occurrence only
        if ($updated -eq $raw -and $raw -notmatch [regex]::Escape($Version)) {
            throw "Could not locate a `"version`" property to update in '$Path'."
        }
        Set-Content -Path $Path -Value $updated -NoNewline
    }
    else {
        Set-Content -Path $Path -Value $Version
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Builds a markdown changelog entry from conventional commits.
    .DESCRIPTION
        Groups commits into Breaking Changes / Features / Fixes sections.
        Commits of other types (chore, docs, ...) are excluded. Headings with
        no matching commits are omitted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$Date,

        [Parameter(Mandatory)]
        [string[]]$Commits
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes    = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $Commits) {
        $subject = ($commit -split "`n")[0].Trim()
        # Strip the conventional prefix ("feat(scope)!: " etc.) for display.
        $description = $subject -replace '^\s*\w+(\([^)]*\))?!?:\s*', ''

        if ($commit -match 'BREAKING[ -]CHANGE' -or $subject -match '^\s*\w+(\([^)]*\))?!:') {
            $breaking.Add($description)
        }
        elseif ($subject -match '^\s*feat(\([^)]*\))?:') {
            $features.Add($description)
        }
        elseif ($subject -match '^\s*fix(\([^)]*\))?:') {
            $fixes.Add($description)
        }
        # other types are intentionally excluded from the changelog
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")
    foreach ($section in @(
            @{ Title = 'Breaking Changes'; Items = $breaking },
            @{ Title = 'Features';         Items = $features },
            @{ Title = 'Fixes';            Items = $fixes })) {
        if ($section.Items.Count -gt 0) {
            $lines.Add('')
            $lines.Add("### $($section.Title)")
            $lines.Add('')
            foreach ($item in $section.Items) { $lines.Add("- $item") }
        }
    }

    return ($lines -join "`n") + "`n"
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Full pipeline: read version, determine bump from a commit log file,
        update the version file, prepend a changelog entry, return a result.
    .PARAMETER VersionFile
        Path to the version file (plain text or package.json).
    .PARAMETER CommitLog
        Path to a text file with one commit message per line (a mock of
        `git log --pretty=%s`, blank lines ignored).
    .PARAMETER ChangelogPath
        Path to the changelog file to create/prepend. Not written when no
        bump is required.
    .OUTPUTS
        [pscustomobject] with OldVersion, NewVersion, BumpType, ChangelogEntry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionFile,

        [Parameter(Mandatory)]
        [string]$CommitLog,

        [Parameter(Mandatory)]
        [string]$ChangelogPath
    )

    if (-not (Test-Path -Path $CommitLog -PathType Leaf)) {
        throw "Commit log file not found: '$CommitLog'."
    }

    $oldVersion = Get-CurrentVersion -Path $VersionFile
    $commits = @(Get-Content -Path $CommitLog | Where-Object { $_.Trim() })
    if ($commits.Count -eq 0) {
        throw "Commit log '$CommitLog' contains no commit messages."
    }

    $bumpType = Get-BumpType -Commits $commits
    $newVersion = Step-Version -Version $oldVersion -BumpType $bumpType

    $entry = $null
    if ($bumpType -ne 'none') {
        Set-CurrentVersion -Path $VersionFile -Version $newVersion
        $entry = New-ChangelogEntry -Version $newVersion `
            -Date (Get-Date -Format 'yyyy-MM-dd') -Commits $commits

        # Prepend the entry, keeping a leading "# Changelog" title (and any
        # existing entries) below it.
        if (Test-Path -Path $ChangelogPath -PathType Leaf) {
            $existing = (Get-Content -Path $ChangelogPath -Raw).TrimEnd()
            if ($existing -match '^(# .*?)(\r?\n)+([\s\S]*)$') {
                $newContent = "$($Matches[1])`n`n$entry`n$($Matches[3])`n"
            }
            else {
                $newContent = "$entry`n$existing`n"
            }
        }
        else {
            $newContent = "# Changelog`n`n$entry"
        }
        Set-Content -Path $ChangelogPath -Value $newContent -NoNewline
    }

    return [pscustomobject]@{
        OldVersion     = $oldVersion
        NewVersion     = $newVersion
        BumpType       = $bumpType
        ChangelogEntry = $entry
    }
}

Export-ModuleMember -Function Get-BumpType, Step-Version, Get-CurrentVersion, Set-CurrentVersion, New-ChangelogEntry, Invoke-VersionBump
