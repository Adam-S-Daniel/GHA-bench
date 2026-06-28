#Requires -Version 7.0

<#
.SYNOPSIS
    Semantic Version Bumper module.

.DESCRIPTION
    Pure-logic functions for a conventional-commits based semantic version
    bumper. The module deliberately keeps all behaviour in small, individually
    testable functions so the logic can be verified with Pester independently of
    the CLI wrapper (Invoke-VersionBump.ps1) and the GitHub Actions pipeline.

    Conventional Commits mapping (https://www.conventionalcommits.org):
        feat:            -> minor bump
        fix:             -> patch bump
        <type>!: / BREAKING CHANGE -> major bump
        other types      -> no bump
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Version reading
# ---------------------------------------------------------------------------

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Read the current semantic version from a version file or package.json.

    .DESCRIPTION
        Supports two input shapes:
          * package.json (any *.json file) -> reads the top-level "version" field.
          * A plain text version file       -> extracts the first semver-looking
            token (e.g. a VERSION file containing "1.4.2" or "v1.4.2").

        An optional leading "v" is tolerated but stripped from the returned
        value so callers always get a bare "MAJOR.MINOR.PATCH" string.

    .PARAMETER Path
        Path to the version file or package.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'."
    }

    # JSON manifests (package.json and friends) keep the version in a field.
    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        $raw = Get-Content -LiteralPath $Path -Raw
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }
        if (-not ($json.PSObject.Properties.Name -contains 'version') -or [string]::IsNullOrWhiteSpace([string]$json.version)) {
            throw "JSON version file '$Path' does not contain a 'version' field."
        }
        return (Convert-ToSemverCore -Version ([string]$json.version) -Source $Path)
    }

    # Plain version file: pull the first semver token out of the file contents.
    $content = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($content, 'v?\d+\.\d+\.\d+')
    if (-not $match.Success) {
        throw "No semantic version (MAJOR.MINOR.PATCH) found in version file '$Path'."
    }
    return (Convert-ToSemverCore -Version $match.Value -Source $Path)
}

function Convert-ToSemverCore {
    # Strip an optional leading "v" and validate the MAJOR.MINOR.PATCH shape.
    # Internal helper (not exported); throws on anything that is not a clean
    # three-part semver core.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Version,
        [string] $Source = '<input>'
    )

    $trimmed = $Version.Trim().TrimStart('v', 'V')
    if ($trimmed -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid semantic version '$Version' from '$Source' (expected MAJOR.MINOR.PATCH)."
    }
    return $trimmed
}

# ---------------------------------------------------------------------------
# Conventional commit parsing
# ---------------------------------------------------------------------------

function ConvertFrom-ConventionalCommit {
    <#
    .SYNOPSIS
        Parse a single commit message into its conventional-commit parts.

    .DESCRIPTION
        Recognises the header form "<type>(<scope>)!: <description>". The scope
        and the "!" breaking marker are optional. A commit is also treated as
        breaking if it contains a "BREAKING CHANGE" / "BREAKING-CHANGE" token
        anywhere in the message (the Conventional Commits footer convention).

        Returns a PSCustomObject with: Type, Scope, Breaking, Description,
        IsConventional. Non-conventional messages return IsConventional = $false
        with the original text as Description.

    .PARAMETER Message
        The commit message (subject line, optionally including a footer token).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    $text = $Message.Trim()

    # A "BREAKING CHANGE" / "BREAKING-CHANGE" token marks a breaking change
    # regardless of type (Conventional Commits footer style).
    $breakingToken = $text -match 'BREAKING[ -]CHANGE'

    # Header pattern: type, optional (scope), optional !, colon, description.
    $headerPattern = '^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?:\s*(?<desc>.*)$'
    $m = [regex]::Match($text, $headerPattern)

    if (-not $m.Success) {
        return [pscustomobject]@{
            Type           = $null
            Scope          = $null
            Breaking       = $breakingToken
            Description    = $text
            IsConventional = $false
        }
    }

    return [pscustomobject]@{
        Type           = $m.Groups['type'].Value.ToLowerInvariant()
        Scope          = if ($m.Groups['scope'].Success) { $m.Groups['scope'].Value } else { $null }
        Breaking       = ($m.Groups['bang'].Success -or $breakingToken)
        # Strip a trailing BREAKING CHANGE footer from the human-facing text.
        Description    = ($m.Groups['desc'].Value -replace '\s*BREAKING[ -]CHANGE.*$', '').Trim()
        IsConventional = $true
    }
}

function Get-CommitBumpType {
    <#
    .SYNOPSIS
        Determine the highest-priority semantic-version bump for a set of commits.

    .DESCRIPTION
        Precedence (highest first):
            breaking change -> 'major'
            feat            -> 'minor'
            fix             -> 'patch'
            anything else   -> 'none'

    .PARAMETER Commits
        Array of raw commit message strings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits
    )

    $bump = 'none'
    foreach ($raw in $Commits) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $c = ConvertFrom-ConventionalCommit -Message $raw

        if ($c.Breaking) {
            # Breaking always wins; we can stop scanning.
            return 'major'
        }
        if ($c.Type -eq 'feat' -and $bump -ne 'minor') {
            $bump = 'minor'
        }
        elseif ($c.Type -eq 'fix' -and $bump -eq 'none') {
            $bump = 'patch'
        }
    }
    return $bump
}

# ---------------------------------------------------------------------------
# Version stepping
# ---------------------------------------------------------------------------

function Get-NextVersion {
    <#
    .SYNOPSIS
        Compute the next semantic version from a current version and a bump type.

    .PARAMETER CurrentVersion
        The current "MAJOR.MINOR.PATCH" string.

    .PARAMETER BumpType
        One of: major, minor, patch, none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $CurrentVersion,
        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string] $BumpType
    )

    $core = Convert-ToSemverCore -Version $CurrentVersion -Source 'Get-NextVersion'
    $parts = $core.Split('.')
    [int]$major = $parts[0]
    [int]$minor = $parts[1]
    [int]$patch = $parts[2]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { } # unchanged
    }

    return "$major.$minor.$patch"
}

# ---------------------------------------------------------------------------
# Changelog generation
# ---------------------------------------------------------------------------

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Build a Markdown changelog entry for a release from its commits.

    .DESCRIPTION
        Produces a "Keep a Changelog"/conventional-changelog style block with a
        version header, the release date, and sections grouped by type:
        BREAKING CHANGES, Features (feat), Bug Fixes (fix), and Other Changes
        (everything else that is conventional). Returns the entry as a string.

    .PARAMETER Version
        The new version number for the header.

    .PARAMETER Commits
        Array of raw commit message strings.

    .PARAMETER Date
        Release date string (e.g. "2026-06-28"). Defaults to today (UTC).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]   $Version,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits,
        [string] $Date = ([System.DateTime]::UtcNow.ToString('yyyy-MM-dd'))
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes    = [System.Collections.Generic.List[string]]::new()
    $other    = [System.Collections.Generic.List[string]]::new()

    foreach ($raw in $Commits) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $c = ConvertFrom-ConventionalCommit -Message $raw

        # Prefix the description with its scope when present, e.g. "**api:** ...".
        $line = if ($c.Scope) { "**$($c.Scope):** $($c.Description)" } else { $c.Description }

        if ($c.Breaking) { $breaking.Add($line) }

        switch ($c.Type) {
            'feat'  { $features.Add($line) }
            'fix'   { $fixes.Add($line) }
            default {
                # Only list other *conventional* commits; skip noise that isn't
                # a recognised commit at all unless it was breaking.
                if ($c.IsConventional -and -not $c.Breaking) { $other.Add($line) }
            }
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## [$Version] - $Date")
    [void]$sb.AppendLine()

    $appendSection = {
        param([string] $Title, [System.Collections.Generic.List[string]] $Items)
        if ($Items.Count -gt 0) {
            [void]$sb.AppendLine("### $Title")
            [void]$sb.AppendLine()
            foreach ($i in $Items) { [void]$sb.AppendLine("* $i") }
            [void]$sb.AppendLine()
        }
    }

    & $appendSection '⚠ BREAKING CHANGES' $breaking
    & $appendSection 'Features' $features
    & $appendSection 'Bug Fixes' $fixes
    & $appendSection 'Other Changes' $other

    return $sb.ToString().TrimEnd() + "`n"
}

# ---------------------------------------------------------------------------
# Commit-log reading and version-file writing (I/O)
# ---------------------------------------------------------------------------

function ConvertFrom-CommitLog {
    <#
    .SYNOPSIS
        Read a commit-log fixture file into an array of commit message strings.

    .DESCRIPTION
        The log format is one commit subject per line (matching
        `git log --pretty=format:%s`). Blank lines and lines beginning with "#"
        (comments) are ignored. This keeps fixtures readable and easy to author.

    .PARAMETER Path
        Path to the commit-log file.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Commit log file not found: '$Path'."
    }

    $lines = Get-Content -LiteralPath $Path
    $commits = foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        $trimmed
    }

    # Always hand back a real array (even for zero/one commit). The unary comma
    # wraps the array so the pipeline does not unwrap a single element back to a
    # scalar string in the caller.
    return , @($commits)
}

function Set-VersionFile {
    <#
    .SYNOPSIS
        Write a new version back to a version file or package.json.

    .DESCRIPTION
        For package.json the "version" field is replaced in place via a targeted
        regex substitution so the rest of the file (ordering, formatting,
        comments-as-content) is preserved exactly. For a plain version file the
        whole file is replaced with the new version string.

    .PARAMETER Path
        Path to the version file to update.

    .PARAMETER Version
        The new "MAJOR.MINOR.PATCH" version string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Version
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'."
    }

    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        $raw = Get-Content -LiteralPath $Path -Raw
        # Replace only the first "version": "..." occurrence to preserve layout.
        $updated = [regex]::Replace(
            $raw,
            '("version"\s*:\s*")[^"]*(")',
            "`${1}$Version`${2}",
            [System.Text.RegularExpressions.RegexOptions]::None,
            [TimeSpan]::FromSeconds(5))
        if ($updated -eq $raw) {
            throw "Could not find a 'version' field to update in '$Path'."
        }
        # Write without a trailing newline change to keep the file stable.
        Set-Content -LiteralPath $Path -Value $updated -NoNewline
    }
    else {
        # Plain version file: a single line containing the version.
        Set-Content -LiteralPath $Path -Value $Version
    }
}

# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Run the full bump: read version + commits, compute next version, update
        the version file, prepend a changelog entry, and return a result object.

    .DESCRIPTION
        Ties the pure functions together. Throws a meaningful error when the
        commits do not warrant any version bump (so callers/CI can decide what
        to do). Returns a PSCustomObject describing the result:
            PreviousVersion, NewVersion, BumpType, CommitCount, ChangelogEntry.

    .PARAMETER VersionFile
        Path to the version file (or package.json) to read and update.

    .PARAMETER CommitLog
        Path to the commit-log fixture file (one subject per line).

    .PARAMETER ChangelogFile
        Path to the changelog file to prepend the new entry to. Created if absent.

    .PARAMETER Date
        Release date string for the changelog entry. Defaults to today (UTC).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $VersionFile,
        [Parameter(Mandatory)] [string] $CommitLog,
        [string] $ChangelogFile = 'CHANGELOG.md',
        [string] $Date = ([System.DateTime]::UtcNow.ToString('yyyy-MM-dd'))
    )

    $previous = Get-CurrentVersion -Path $VersionFile
    # @(...) guards against PowerShell unwrapping a single-element result back to
    # a scalar, which would make $commits.Count fail under Set-StrictMode.
    $commits  = @(ConvertFrom-CommitLog -Path $CommitLog)
    $bumpType = Get-CommitBumpType -Commits $commits

    if ($bumpType -eq 'none') {
        throw "No version bump required: none of the $($commits.Count) commit(s) are feat/fix/breaking changes."
    }

    $newVersion = Get-NextVersion -CurrentVersion $previous -BumpType $bumpType

    # Update the version file in place.
    Set-VersionFile -Path $VersionFile -Version $newVersion

    # Build and prepend the changelog entry (newest entries on top).
    $entry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date
    $existing = ''
    if (Test-Path -LiteralPath $ChangelogFile -PathType Leaf) {
        $existing = Get-Content -LiteralPath $ChangelogFile -Raw
    }
    else {
        # Seed a new changelog with a standard header.
        $existing = "# Changelog`n`nAll notable changes to this project are documented here.`n"
    }

    # Insert the new entry above the first existing release heading ("## ..."),
    # so releases stay newest-first while any title/intro preamble remains at the
    # top. If there is no existing release heading yet, append after the preamble.
    $firstRelease = [regex]::Match($existing, '(?m)^##\s')
    if ($firstRelease.Success) {
        $head = $existing.Substring(0, $firstRelease.Index).TrimEnd()
        $tail = $existing.Substring($firstRelease.Index)
        $combined = $head + "`n`n" + $entry + "`n" + $tail
    }
    else {
        $combined = $existing.TrimEnd() + "`n`n" + $entry
    }
    Set-Content -LiteralPath $ChangelogFile -Value $combined -NoNewline

    return [pscustomobject]@{
        PreviousVersion = $previous
        NewVersion      = $newVersion
        BumpType        = $bumpType
        CommitCount     = $commits.Count
        ChangelogEntry  = $entry
    }
}

Export-ModuleMember -Function @(
    'Get-CurrentVersion',
    'ConvertFrom-ConventionalCommit',
    'Get-CommitBumpType',
    'Get-NextVersion',
    'New-ChangelogEntry',
    'ConvertFrom-CommitLog',
    'Set-VersionFile',
    'Invoke-VersionBump'
)
