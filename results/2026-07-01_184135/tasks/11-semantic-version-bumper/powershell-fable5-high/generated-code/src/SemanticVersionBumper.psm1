<#
.SYNOPSIS
    Semantic version bumping based on conventional commit messages.

.DESCRIPTION
    Provides functions to:
      * parse semantic version strings                  (ConvertFrom-SemVer)
      * split mock commit-log fixtures into commits     (Split-CommitLog)
      * classify commits into a bump type               (Get-BumpType)
    Built incrementally with red/green TDD; see tests/unit.
#>

Set-StrictMode -Version Latest

function ConvertFrom-SemVer {
    <#
    .SYNOPSIS
        Parses a "MAJOR.MINOR.PATCH" string into its numeric components.
    #>
    [CmdletBinding()]
    param(
        # Version string to parse; must be plain MAJOR.MINOR.PATCH.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Version
    )

    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "'$Version' is not a valid semantic version (expected MAJOR.MINOR.PATCH, e.g. 1.2.3)."
    }

    [pscustomobject]@{
        Major = [int]$Matches[1]
        Minor = [int]$Matches[2]
        Patch = [int]$Matches[3]
    }
}

function Split-CommitLog {
    <#
    .SYNOPSIS
        Reads a commit-log file and returns one string per commit message.

    .DESCRIPTION
        The commit-log format used by the fixtures (and by the CI pipeline)
        is a plain text file where commit messages are separated by lines
        containing only "---". A message may span multiple lines (subject,
        blank line, body/footers), mirroring `git log` output.
    #>
    [CmdletBinding()]
    param(
        # Path to the commit log file.
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Commit log file not found: '$Path'. Provide a text file with commit messages separated by '---' lines."
    }

    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    # Split on delimiter lines ("---" alone on a line), then trim each block.
    $blocks = ($raw -split '(?m)^\s*---\s*$') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }

    return @($blocks)
}

function Get-BumpType {
    <#
    .SYNOPSIS
        Determines the semantic bump for a set of conventional commits.

    .DESCRIPTION
        Rules (highest severity wins across all commits):
          * "type!:" subject marker or a BREAKING CHANGE / BREAKING-CHANGE
            footer anywhere in the message  -> major
          * feat / feat(scope)              -> minor
          * fix / fix(scope)                -> patch
          * anything else (chore, docs, non-conventional, ...) -> none
    #>
    [CmdletBinding()]
    param(
        # Full commit messages (subject + optional body), one string each.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits
    )

    $bump = 'none'
    foreach ($commit in $Commits) {
        $subject = ($commit -split "`r?`n")[0]

        # Conventional commit subject: type(optional-scope)!: description
        $isConventional = $subject -match '^(?<type>[a-zA-Z]+)(\([^)]*\))?(?<bang>!)?:\s+.+$'
        $type = if ($isConventional) { $Matches['type'].ToLowerInvariant() } else { '' }
        $hasBang = $isConventional -and $Matches['bang'] -eq '!'
        $hasFooter = $commit -match '(?m)^BREAKING[ -]CHANGE:'

        if ($hasBang -or $hasFooter) {
            return 'major'   # nothing outranks major; short-circuit
        }
        if ($type -eq 'feat') {
            $bump = 'minor'
        }
        elseif ($type -eq 'fix' -and $bump -ne 'minor') {
            $bump = 'patch'
        }
    }
    return $bump
}

function Step-Version {
    <#
    .SYNOPSIS
        Computes the next semantic version for a given bump type.
    #>
    [CmdletBinding()]
    param(
        # Current version as MAJOR.MINOR.PATCH.
        [Parameter(Mandatory)]
        [string]$Version,

        # Bump severity as returned by Get-BumpType.
        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    $v = ConvertFrom-SemVer -Version $Version
    switch ($BumpType) {
        'major' { '{0}.0.0' -f ($v.Major + 1) }
        'minor' { '{0}.{1}.0' -f $v.Major, ($v.Minor + 1) }
        'patch' { '{0}.{1}.{2}' -f $v.Major, $v.Minor, ($v.Patch + 1) }
        'none'  { $Version }
    }
}

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file.

    .DESCRIPTION
        Supports two formats, selected by file name:
          * package.json  -> the top-level "version" field
          * anything else -> the whole file is the version string
    #>
    [CmdletBinding()]
    param(
        # Path to VERSION file or package.json.
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'."
    }

    $raw = Get-Content -Path $Path -Raw
    if ((Split-Path $Path -Leaf) -eq 'package.json') {
        try {
            $json = $raw | ConvertFrom-Json
        }
        catch {
            throw "'$Path' is not valid JSON: $($_.Exception.Message)"
        }
        if (-not ($json.PSObject.Properties.Name -contains 'version')) {
            throw "'$Path' does not contain a `"version`" field."
        }
        $version = [string]$json.version
    }
    else {
        $version = $raw.Trim()
    }

    # Validate before returning so callers get a clear early failure.
    ConvertFrom-SemVer -Version $version | Out-Null
    return $version
}

function Set-VersionFile {
    <#
    .SYNOPSIS
        Writes the new version back to the version file.

    .DESCRIPTION
        For package.json the "version" field is updated in place via a
        targeted regex replace so formatting and key order are preserved;
        for plain files the whole content becomes the version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        # New MAJOR.MINOR.PATCH version to persist.
        [Parameter(Mandatory)]
        [string]$Version
    )

    ConvertFrom-SemVer -Version $Version | Out-Null

    if ((Split-Path $Path -Leaf) -eq 'package.json') {
        # Read to validate structure first; fail loudly on broken files.
        Get-CurrentVersion -Path $Path | Out-Null
        $raw = Get-Content -Path $Path -Raw
        $updated = $raw -replace '("version"\s*:\s*")[^"]*(")', ('${1}' + $Version + '${2}')
        Set-Content -Path $Path -Value $updated -NoNewline
    }
    else {
        Set-Content -Path $Path -Value $Version
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Renders a markdown changelog entry from conventional commits.

    .DESCRIPTION
        Commits are grouped into "Breaking Changes", "Features" and
        "Bug Fixes"; commits of other/unknown types are skipped. Scopes
        are rendered as bold prefixes ("- **api:** description").
        The date is a parameter (not "now") so output is deterministic
        and therefore testable.
    #>
    [CmdletBinding()]
    param(
        # Version the entry describes.
        [Parameter(Mandatory)]
        [string]$Version,

        # Full commit messages contributing to this release.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits,

        # Release date rendered in the heading (yyyy-MM-dd).
        [Parameter(Mandatory)]
        [string]$Date
    )

    $sections = [ordered]@{
        'Breaking Changes' = [System.Collections.Generic.List[string]]::new()
        'Features'         = [System.Collections.Generic.List[string]]::new()
        'Bug Fixes'        = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($commit in $Commits) {
        $subject = ($commit -split "`r?`n")[0]
        if ($subject -notmatch '^(?<type>[a-zA-Z]+)(\((?<scope>[^)]*)\))?(?<bang>!)?:\s+(?<desc>.+)$') {
            continue   # non-conventional commits don't appear in the changelog
        }

        $scope = $Matches['scope']
        $bullet = if ($scope) { "- **$($scope):** $($Matches['desc'])" } else { "- $($Matches['desc'])" }
        $isBreaking = $Matches['bang'] -eq '!' -or $commit -match '(?m)^BREAKING[ -]CHANGE:'

        if ($isBreaking) { $sections['Breaking Changes'].Add($bullet) }
        elseif ($Matches['type'] -eq 'feat') { $sections['Features'].Add($bullet) }
        elseif ($Matches['type'] -eq 'fix') { $sections['Bug Fixes'].Add($bullet) }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")
    foreach ($name in $sections.Keys) {
        if ($sections[$name].Count -eq 0) { continue }   # omit empty sections
        $lines.Add('')
        $lines.Add("### $name")
        $sections[$name] | ForEach-Object { $lines.Add($_) }
    }
    return ($lines -join "`n")
}

function Add-ChangelogEntry {
    <#
    .SYNOPSIS
        Prepends an entry to CHANGELOG.md, keeping newest releases on top.
    #>
    [CmdletBinding()]
    param(
        # Path to the changelog file (created if absent).
        [Parameter(Mandatory)]
        [string]$Path,

        # Rendered markdown entry from New-ChangelogEntry.
        [Parameter(Mandatory)]
        [string]$Entry
    )

    $header = '# Changelog'
    if (Test-Path -Path $Path -PathType Leaf) {
        $existing = (Get-Content -Path $Path -Raw).TrimEnd()
        if ($existing.StartsWith($header)) {
            # Insert the new entry between the header and older entries.
            $body = $existing.Substring($header.Length).TrimStart("`r", "`n")
            $content = "$header`n`n$Entry`n`n$body"
        }
        else {
            $content = "$Entry`n`n$existing"
        }
    }
    else {
        $content = "$header`n`n$Entry"
    }
    Set-Content -Path $Path -Value ($content.TrimEnd() + "`n") -NoNewline
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Full pipeline: read version, classify commits, bump, write
        version file + changelog, and return the new version string.

    .DESCRIPTION
        When the commits require no release (bump type "none") nothing is
        written and the current version is returned unchanged.
    #>
    [CmdletBinding()]
    param(
        # VERSION file or package.json holding the current version.
        [Parameter(Mandatory)]
        [string]$VersionFile,

        # Commit log fixture ('---'-delimited commit messages).
        [Parameter(Mandatory)]
        [string]$CommitLogFile,

        # Changelog to prepend the release notes to.
        [Parameter(Mandatory)]
        [string]$ChangelogFile,

        # Release date; defaults to today so CI needs no extra input.
        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    $current = Get-CurrentVersion -Path $VersionFile
    $commits = Split-CommitLog -Path $CommitLogFile
    $bump = Get-BumpType -Commits $commits

    if ($bump -eq 'none') {
        Write-Verbose "No release-worthy commits found; staying at $current."
        return $current
    }

    $next = Step-Version -Version $current -BumpType $bump
    Set-VersionFile -Path $VersionFile -Version $next
    $entry = New-ChangelogEntry -Version $next -Commits $commits -Date $Date
    Add-ChangelogEntry -Path $ChangelogFile -Entry $entry

    Write-Verbose "Bumped $current -> $next ($bump)."
    return $next
}

Export-ModuleMember -Function ConvertFrom-SemVer, Split-CommitLog, Get-BumpType,
    Step-Version, Get-CurrentVersion, Set-VersionFile,
    New-ChangelogEntry, Add-ChangelogEntry, Invoke-VersionBump
