#Requires -Version 7.0

<#
.SYNOPSIS
    Semantic Version Bumper.

.DESCRIPTION
    A small library of functions that:
      * read a semantic version from a plain VERSION file or a package.json,
      * inspect Conventional Commit messages to decide the next version
        (feat -> minor, fix -> patch, breaking change -> major),
      * compute and write back the new version,
      * generate a Keep-a-Changelog style changelog entry.

    The functions are intentionally small and pure so they are easy to unit
    test with Pester. Orchestration lives in Invoke-VersionBump.ps1.
#>

Set-StrictMode -Version Latest

# Matches a semantic version: MAJOR.MINOR.PATCH with optional -prerelease and
# +build metadata (see https://semver.org). Capture groups are named so the
# parser is readable.
$script:SemVerPattern = '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>[0-9A-Za-z-.]+))?(?:\+(?<build>[0-9A-Za-z-.]+))?$'

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a VERSION file or package.json.
    .PARAMETER Path
        Path to a plain-text version file (first non-empty line is the version)
        or a package.json (the ".version" property is used).
    .OUTPUTS
        [string] the version, e.g. "1.2.3".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    # Decide whether this is a package.json by file name first, then by content.
    $isJson = ([System.IO.Path]::GetFileName($Path) -ieq 'package.json')

    if ($isJson) {
        try {
            $json = $raw | ConvertFrom-Json
        } catch {
            throw "Could not parse '$Path' as JSON: $($_.Exception.Message)"
        }
        if (-not $json.PSObject.Properties.Name -contains 'version' -or [string]::IsNullOrWhiteSpace([string]$json.version)) {
            throw "package.json '$Path' does not contain a 'version' field."
        }
        $version = [string]$json.version
    } else {
        # Plain version file: take the first non-empty, non-comment line.
        $version = ($raw -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') } |
            Select-Object -First 1)
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "No version string found in '$Path'."
    }

    $version = $version.Trim()
    if ($version -notmatch $script:SemVerPattern) {
        throw "Version '$version' in '$Path' is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }

    return $version
}

# Parses the header line of a Conventional Commit:
#   type(optional-scope)!: description
# e.g. "feat(api)!: rename endpoint". Named groups expose the parts we need.
$script:ConventionalHeaderPattern = '^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]*)\))?(?<breaking>!)?:\s*(?<description>.+)$'

function ConvertTo-ConventionalCommit {
    <#
    .SYNOPSIS
        Parses a single (possibly multi-line) commit message into its parts.
    .OUTPUTS
        [pscustomobject] with Type, Scope, Description, IsBreaking and Raw, or
        $null when the header is not a Conventional Commit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    $lines  = $Message -split "`r?`n"
    $header = ($lines | Select-Object -First 1).Trim()

    $m = [regex]::Match($header, $script:ConventionalHeaderPattern)
    if (-not $m.Success) {
        return $null
    }

    # A breaking change is signalled either by "!" after the type/scope or by a
    # "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer anywhere in the body.
    $isBreaking = $m.Groups['breaking'].Success
    if (-not $isBreaking) {
        $isBreaking = ($Message -match '(?m)^\s*BREAKING[ -]CHANGE\s*:')
    }

    return [pscustomobject]@{
        Type        = $m.Groups['type'].Value.ToLowerInvariant()
        Scope       = $m.Groups['scope'].Value
        Description = $m.Groups['description'].Value.Trim()
        IsBreaking  = [bool] $isBreaking
        Raw         = $Message
    }
}

function Get-VersionBumpType {
    <#
    .SYNOPSIS
        Decides the semantic-version bump implied by a set of commit messages.
    .DESCRIPTION
        Conventional Commits mapping:
          breaking change  -> major
          feat             -> minor
          fix              -> patch
          everything else  -> no bump
        The highest-precedence bump found across all commits wins.
    .OUTPUTS
        [string] one of 'major', 'minor', 'patch', 'none'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits
    )

    # Numeric ranking lets us keep only the most significant bump.
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }
    $result = 'none'

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }

        $parsed = ConvertTo-ConventionalCommit -Message $commit
        if ($null -eq $parsed) { continue }

        $bump = 'none'
        if ($parsed.IsBreaking) {
            $bump = 'major'
        } elseif ($parsed.Type -eq 'feat') {
            $bump = 'minor'
        } elseif ($parsed.Type -eq 'fix') {
            $bump = 'patch'
        }

        if ($rank[$bump] -gt $rank[$result]) {
            $result = $bump
        }
    }

    return $result
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version given a bump type.
    .OUTPUTS
        [string] the next version. For BumpType 'none' the input is returned
        unchanged (with any pre-release/build metadata preserved).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string] $BumpType
    )

    $m = [regex]::Match($Version, $script:SemVerPattern)
    if (-not $m.Success) {
        throw "Cannot bump '$Version': it is not a valid semantic version."
    }

    if ($BumpType -eq 'none') {
        return $Version
    }

    $major = [int] $m.Groups['major'].Value
    $minor = [int] $m.Groups['minor'].Value
    $patch = [int] $m.Groups['patch'].Value

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
    }

    # Bumping always produces a clean release version (pre-release/build dropped).
    return "$major.$minor.$patch"
}

function Get-CommitsFromFile {
    <#
    .SYNOPSIS
        Reads a mock/real commit log file into an array of commit messages.
    .DESCRIPTION
        Two supported layouts:
          * one commit per line (the default, matching `git log --format=%s`), or
          * multi-line commits separated by a line containing only "---", which
            allows commit bodies / "BREAKING CHANGE:" footers to be expressed.
        Blank entries are ignored.
    .OUTPUTS
        [string[]] commit messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Commit log file not found: '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { $raw = '' }

    if ($raw -match '(?m)^\s*---\s*$') {
        # Multi-line records separated by a "---" line.
        $records = $raw -split '(?m)^\s*---\s*$'
    } else {
        # One commit per line.
        $records = $raw -split "`r?`n"
    }

    return @(
        $records |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Writes the new version back to a plain VERSION file or package.json.
    .DESCRIPTION
        For package.json the "version" field is replaced with a targeted regex so
        the rest of the file (key order, indentation) is preserved. For a plain
        file the whole file is replaced with the new version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Cannot update version: file not found: '$Path'."
    }

    $isJson = ([System.IO.Path]::GetFileName($Path) -ieq 'package.json')

    if ($isJson) {
        $raw = Get-Content -LiteralPath $Path -Raw
        # Replace the value of the first "version": "x.y.z" pair only.
        $pattern = '("version"\s*:\s*")[^"]*(")'
        if ($raw -notmatch $pattern) {
            throw "package.json '$Path' has no 'version' field to update."
        }
        $updated = [regex]::Replace($raw, $pattern, "`${1}$NewVersion`${2}", 1)
        Set-Content -LiteralPath $Path -Value $updated -NoNewline
    } else {
        # Plain version file: a single line with a trailing newline.
        Set-Content -LiteralPath $Path -Value $NewVersion
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Builds a Keep-a-Changelog style markdown entry for a release.
    .DESCRIPTION
        Commits are grouped into BREAKING CHANGES, Features (feat) and Bug Fixes
        (fix). Only those three categories are surfaced; other commit types
        (chore, docs, ...) are intentionally omitted from the entry.
    .OUTPUTS
        [string] the markdown entry (without surrounding changelog title).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits,

        [Parameter()]
        [string] $Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes    = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $Commits) {
        $parsed = ConvertTo-ConventionalCommit -Message $commit
        if ($null -eq $parsed) { continue }

        if ($parsed.IsBreaking) {
            $scope = if ($parsed.Scope) { "**$($parsed.Scope):** " } else { '' }
            $breaking.Add("- $scope$($parsed.Description)")
        }
        if ($parsed.Type -eq 'feat') {
            $features.Add("- $($parsed.Description)")
        } elseif ($parsed.Type -eq 'fix') {
            $fixes.Add("- $($parsed.Description)")
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void] $sb.AppendLine("## [$Version] - $Date")
    [void] $sb.AppendLine()

    if ($breaking.Count -gt 0) {
        [void] $sb.AppendLine('### BREAKING CHANGES')
        [void] $sb.AppendLine()
        foreach ($line in $breaking) { [void] $sb.AppendLine($line) }
        [void] $sb.AppendLine()
    }
    if ($features.Count -gt 0) {
        [void] $sb.AppendLine('### Features')
        [void] $sb.AppendLine()
        foreach ($line in $features) { [void] $sb.AppendLine($line) }
        [void] $sb.AppendLine()
    }
    if ($fixes.Count -gt 0) {
        [void] $sb.AppendLine('### Bug Fixes')
        [void] $sb.AppendLine()
        foreach ($line in $fixes) { [void] $sb.AppendLine($line) }
        [void] $sb.AppendLine()
    }

    if ($breaking.Count -eq 0 -and $features.Count -eq 0 -and $fixes.Count -eq 0) {
        [void] $sb.AppendLine('_No user-facing changes._')
        [void] $sb.AppendLine()
    }

    return $sb.ToString().TrimEnd() + "`n"
}

function Add-ChangelogEntry {
    <#
    .SYNOPSIS
        Prepends a changelog entry to CHANGELOG.md (creating it if necessary).
    .DESCRIPTION
        The new entry is inserted directly under the "# Changelog" title so the
        newest release is always on top. A standard header is written if the file
        does not yet exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Entry
    )

    $title  = '# Changelog'
    $header = "$title`n`nAll notable changes to this project are documented here.`nThe format is based on [Keep a Changelog](https://keepachangelog.com).`n"

    if (-not (Test-Path -LiteralPath $Path)) {
        $body = "$header`n$($Entry.TrimEnd())`n"
        Set-Content -LiteralPath $Path -Value $body
        return
    }

    $existing = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $existing) { $existing = '' }

    $lines = $existing -split "`r?`n", 2
    if ($lines[0] -match '^\s*#\s') {
        # Keep the existing title line, insert the entry right after it.
        $titleLine = $lines[0]
        $rest      = if ($lines.Count -gt 1) { $lines[1] } else { '' }
        $body      = "$titleLine`n`n$($Entry.TrimEnd())`n`n$($rest.TrimStart())"
    } else {
        # No recognisable title: add one and place the entry on top.
        $body = "$header`n$($Entry.TrimEnd())`n`n$existing"
    }

    Set-Content -LiteralPath $Path -Value $body.TrimEnd() -NoNewline
    Add-Content -LiteralPath $Path -Value ''
}

Export-ModuleMember -Function `
    Get-CurrentVersion, `
    Get-VersionBumpType, `
    ConvertTo-ConventionalCommit, `
    Get-NextVersion, `
    Get-CommitsFromFile, `
    Update-VersionFile, `
    New-ChangelogEntry, `
    Add-ChangelogEntry
