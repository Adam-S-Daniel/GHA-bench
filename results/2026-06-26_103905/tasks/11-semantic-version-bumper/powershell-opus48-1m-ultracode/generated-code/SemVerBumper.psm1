<#
    SemVerBumper.psm1

    A small, dependency-free PowerShell module that implements semantic-version
    bumping driven by Conventional Commits.

    Public functions:
      ConvertTo-SemVerObject  - parse a semver string into its components
      Get-CommitBumpType      - classify a single commit message
      Get-VersionBumpType     - reduce many commits to the highest bump level
      Get-NextVersion         - compute the next version from current + bump
      New-ChangelogEntry      - render a markdown changelog block from commits
      Get-CurrentVersion      - read the current version from a file or package.json
      Update-VersionFile      - write a new version back to a file or package.json
      Update-Changelog        - prepend a changelog entry to CHANGELOG.md
      Read-CommitLog          - parse a delimited mock commit-log fixture

    The functions are intentionally pure where possible (no hidden I/O) so they
    are easy to unit-test with Pester. File-touching helpers take explicit paths.
#>

Set-StrictMode -Version Latest

# Canonical SemVer 2.0.0 grammar (https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string)
# Captures: Major, Minor, Patch, optional Prerelease, optional Build metadata.
$script:SemVerRegex = @'
^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
'@

function ConvertTo-SemVerObject {
    <#
    .SYNOPSIS
        Parse a semantic-version string into a structured object.
    .DESCRIPTION
        Validates the input against the SemVer 2.0.0 grammar and returns a
        [pscustomobject] with Major/Minor/Patch (integers) plus optional
        Prerelease and Build strings. Throws a descriptive error otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $trimmed = $Version.Trim()
    $match = [regex]::Match($trimmed, $script:SemVerRegex)
    if (-not $match.Success) {
        throw "Version '$Version' is not a valid semantic version (expected MAJOR.MINOR.PATCH[-prerelease][+build])."
    }

    [pscustomobject]@{
        Major      = [int]$match.Groups['major'].Value
        Minor      = [int]$match.Groups['minor'].Value
        Patch      = [int]$match.Groups['patch'].Value
        Prerelease = if ($match.Groups['prerelease'].Success) { $match.Groups['prerelease'].Value } else { $null }
        Build      = if ($match.Groups['build'].Success) { $match.Groups['build'].Value } else { $null }
    }
}

# Conventional Commit subject grammar: <type>[optional scope][optional !]: <desc>
# e.g. "feat(api)!: drop v1". The trailing-! and a "BREAKING CHANGE" footer both
# signal a breaking change.
$script:ConventionalRegex = '^(?<type>[a-zA-Z]+)(?<scope>\([^)]*\))?(?<breaking>!)?:\s*(?<desc>.*)$'

function Get-CommitBumpType {
    <#
    .SYNOPSIS
        Classify a single commit message into the SemVer level it implies.
    .DESCRIPTION
        Returns one of 'major', 'minor', 'patch' or 'none' based on Conventional
        Commit rules: feat -> minor, fix -> patch, a "!" marker or a
        "BREAKING CHANGE:" footer -> major, everything else -> none.
    .OUTPUTS
        [string] one of major|minor|patch|none
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return 'none' }

    # A "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer anywhere in the body is the
    # strongest signal and always wins.
    if ($Message -match '(?im)^\s*BREAKING[ -]CHANGE\s*:') {
        return 'major'
    }

    # Only the subject (first non-empty line) carries the type/scope/! marker.
    $subject = ($Message -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
    if (-not $subject) { return 'none' }

    $m = [regex]::Match($subject.Trim(), $script:ConventionalRegex)
    if (-not $m.Success) { return 'none' }

    if ($m.Groups['breaking'].Success) { return 'major' }

    switch ($m.Groups['type'].Value.ToLowerInvariant()) {
        'feat' { return 'minor' }
        'fix'  { return 'patch' }
        default { return 'none' }
    }
}

function Get-VersionBumpType {
    <#
    .SYNOPSIS
        Reduce a set of commit messages to the single highest-precedence bump.
    .DESCRIPTION
        Evaluates each commit with Get-CommitBumpType and returns the most
        significant level found. Precedence: major > minor > patch > none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits
    )

    # Numeric rank lets us take a simple max across all commits.
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }
    $names = @('none', 'patch', 'minor', 'major')

    $best = 0
    foreach ($commit in $Commits) {
        $level = Get-CommitBumpType -Message $commit
        if ($rank[$level] -gt $best) { $best = $rank[$level] }
    }
    return $names[$best]
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Compute the next version string given the current version and a bump.
    .DESCRIPTION
        Applies a major/minor/patch bump to the parsed core version, resetting
        lower components per SemVer, and discards any prerelease/build metadata.
        A 'none' bump returns the unchanged core version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [string]$BumpType
    )

    $v = ConvertTo-SemVerObject -Version $CurrentVersion

    switch ($BumpType.ToLowerInvariant()) {
        'major' { return ('{0}.{1}.{2}' -f ($v.Major + 1), 0, 0) }
        'minor' { return ('{0}.{1}.{2}' -f $v.Major, ($v.Minor + 1), 0) }
        'patch' { return ('{0}.{1}.{2}' -f $v.Major, $v.Minor, ($v.Patch + 1)) }
        'none'  { return ('{0}.{1}.{2}' -f $v.Major, $v.Minor, $v.Patch) }
        default { throw "Unknown bump type '$BumpType' (expected major, minor, patch or none)." }
    }
}

# Delimiter used by the mock commit-log fixtures. Each commit's full message
# (subject + optional body/footer) is preceded by a line containing only this
# token. A distinctive token avoids colliding with anything inside a real commit.
$script:CommitDelimiter = '<<<COMMIT>>>'

function Read-CommitLog {
    <#
    .SYNOPSIS
        Parse a delimited mock commit-log fixture into an array of messages.
    .DESCRIPTION
        Splits the file on lines containing only the <<<COMMIT>>> delimiter and
        returns each commit's full message (subject + body), trimmed. Empty
        segments are dropped, so a leading delimiter is fine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Commit log file not found at '$Path'."
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    $delim = [regex]::Escape($script:CommitDelimiter)
    # Split on the delimiter line (anchored, multiline), then trim and drop empties.
    $parts = [regex]::Split($raw, "(?m)^\s*$delim\s*$")
    @($parts | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
}

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Read the current semantic version from a plain file or a package.json.
    .DESCRIPTION
        If the path ends in .json the "version" field is read from the parsed
        JSON; otherwise the file's (trimmed, first non-empty line) contents are
        used. The result is validated as semver before being returned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found at '$Path'."
    }

    if ([System.IO.Path]::GetExtension($Path) -eq '.json') {
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }
        if (-not ($json.PSObject.Properties.Name -contains 'version') -or [string]::IsNullOrWhiteSpace([string]$json.version)) {
            throw "JSON version file '$Path' has no `"version`" field."
        }
        $version = ([string]$json.version).Trim()
    } else {
        $version = (Get-Content -LiteralPath $Path |
            Where-Object { $_.Trim().Length -gt 0 } |
            Select-Object -First 1)
        if ($null -ne $version) { $version = $version.Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Version file '$Path' is empty."
    }

    # Validate (throws a descriptive error if the stored value is not semver).
    $null = ConvertTo-SemVerObject -Version $version
    return $version
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Write a new version back to a plain file or package.json.
    .DESCRIPTION
        For package.json the existing "version": "..." value is replaced in place
        with a regex so the rest of the file's formatting is preserved. For a
        plain file the whole content becomes the new version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found at '$Path'."
    }

    if ([System.IO.Path]::GetExtension($Path) -eq '.json') {
        $raw = Get-Content -LiteralPath $Path -Raw
        $pattern = '("version"\s*:\s*")[^"]*(")'
        if ($raw -notmatch $pattern) {
            throw "Could not locate a `"version`" field to update in '$Path'."
        }
        # ${1}/${2} keep the surrounding quotes & key intact, formatting preserved.
        $updated = [regex]::Replace($raw, $pattern, "`${1}$NewVersion`${2}")
        Set-Content -LiteralPath $Path -Value $updated -Encoding utf8 -NoNewline
    } else {
        # Plain VERSION file: a single trailing newline is conventional.
        Set-Content -LiteralPath $Path -Value $NewVersion -Encoding utf8
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Render a markdown changelog block for a release from its commits.
    .DESCRIPTION
        Commits are grouped into Features (feat), Bug Fixes (fix) and
        BREAKING CHANGES sections under a "## [version] - date" header. Scopes are
        preserved as "(scope)" prefixes. Non-bumping commits are ignored. When no
        notable commits exist a placeholder line is emitted so the entry is never
        blank.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Commits,

        [Parameter()]
        [string]$Date
    )

    if ([string]::IsNullOrWhiteSpace($Date)) {
        $Date = (Get-Date -Format 'yyyy-MM-dd')
    }

    $features = New-Object System.Collections.Generic.List[string]
    $fixes    = New-Object System.Collections.Generic.List[string]
    $breaking = New-Object System.Collections.Generic.List[string]

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }

        $subject = ($commit -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
        $m = [regex]::Match($subject, $script:ConventionalRegex)

        # Human-readable bullet text: "(scope) description", or the raw subject
        # when the commit is not in conventional form.
        if ($m.Success) {
            $scope = if ($m.Groups['scope'].Success) { $m.Groups['scope'].Value + ' ' } else { '' }
            $bullet = ($scope + $m.Groups['desc'].Value).Trim()
            $type = $m.Groups['type'].Value.ToLowerInvariant()
        } else {
            $bullet = $subject
            $type = ''
        }

        # A BREAKING CHANGE footer is surfaced verbatim (the text after the colon).
        $bcMatch = [regex]::Match($commit, '(?im)^\s*BREAKING[ -]CHANGE\s*:\s*(?<text>.*)$')
        if ($bcMatch.Success) {
            $breaking.Add($bcMatch.Groups['text'].Value.Trim())
        } elseif ($m.Success -and $m.Groups['breaking'].Success) {
            # "feat!: ..." with no footer — surface the subject as the breaking note.
            $breaking.Add($bullet)
        }

        switch ($type) {
            'feat' { $features.Add($bullet) }
            'fix'  { $fixes.Add($bullet) }
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## [$Version] - $Date")
    [void]$sb.AppendLine('')

    $wroteSection = $false
    if ($breaking.Count -gt 0) {
        [void]$sb.AppendLine('### BREAKING CHANGES')
        foreach ($b in $breaking) { [void]$sb.AppendLine("- $b") }
        [void]$sb.AppendLine('')
        $wroteSection = $true
    }
    if ($features.Count -gt 0) {
        [void]$sb.AppendLine('### Features')
        foreach ($b in $features) { [void]$sb.AppendLine("- $b") }
        [void]$sb.AppendLine('')
        $wroteSection = $true
    }
    if ($fixes.Count -gt 0) {
        [void]$sb.AppendLine('### Bug Fixes')
        foreach ($b in $fixes) { [void]$sb.AppendLine("- $b") }
        [void]$sb.AppendLine('')
        $wroteSection = $true
    }
    if (-not $wroteSection) {
        [void]$sb.AppendLine('_No notable changes._')
        [void]$sb.AppendLine('')
    }

    return $sb.ToString().TrimEnd() + "`n"
}

function Update-Changelog {
    <#
    .SYNOPSIS
        Prepend a rendered changelog entry to CHANGELOG.md (newest first).
    .DESCRIPTION
        Creates the file with a "# Changelog" header when it does not yet exist.
        Existing release entries are preserved below the header, so the most
        recent release always appears at the top.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Entry
    )

    $header = '# Changelog'
    $entryBlock = $Entry.TrimEnd() + "`n"

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $content = "$header`n`n$entryBlock"
        Set-Content -LiteralPath $Path -Value $content -Encoding utf8
        return
    }

    $existing = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($existing)) {
        Set-Content -LiteralPath $Path -Value "$header`n`n$entryBlock" -Encoding utf8
        return
    }

    # Insert the new entry directly after the top-level "# Changelog" header so
    # older entries stay below it. If there is no header, prepend one.
    $lines = $existing -split "`r?`n"
    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#\s+Changelog') { $headerIndex = $i; break }
    }

    if ($headerIndex -lt 0) {
        $content = "$header`n`n$entryBlock`n$existing"
    } else {
        $before = ($lines[0..$headerIndex] -join "`n")
        $afterStart = $headerIndex + 1
        $after = if ($afterStart -le $lines.Count - 1) { ($lines[$afterStart..($lines.Count - 1)] -join "`n").TrimStart("`n") } else { '' }
        $content = "$before`n`n$entryBlock`n$after".TrimEnd() + "`n"
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding utf8
}

Export-ModuleMember -Function ConvertTo-SemVerObject, Get-CommitBumpType,
    Get-VersionBumpType, Get-NextVersion, Read-CommitLog, Get-CurrentVersion,
    Update-VersionFile, New-ChangelogEntry, Update-Changelog
