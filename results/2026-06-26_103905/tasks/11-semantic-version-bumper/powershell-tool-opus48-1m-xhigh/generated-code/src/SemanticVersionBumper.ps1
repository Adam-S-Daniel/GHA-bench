# SemanticVersionBumper.ps1
#
# Core library for the semantic version bumper. This file defines functions
# only and performs NO work at load time, so it is safe to dot-source from both
# the CLI entry point (bump-version.ps1) and the Pester test suite.

#region Version parsing

function ConvertTo-SemVer {
    <#
    .SYNOPSIS
        Parse a semantic version string into a structured object.
    .DESCRIPTION
        Accepts MAJOR.MINOR.PATCH with an optional leading 'v' and an optional
        '-prerelease' / '+build' suffix (per https://semver.org). Returns a
        PSCustomObject with integer Major/Minor/Patch plus the preserved prefix
        and original text so callers can round-trip the value faithfully.
    .EXAMPLE
        ConvertTo-SemVer 'v1.2.3-rc.1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Version
    )

    $text = $Version.Trim()

    # Capture an optional 'v' prefix so we can restore it on write-back, then the
    # three required numeric components, then optional pre-release / build parts.
    $pattern = '^(?<prefix>v)?(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>[0-9A-Za-z-.]+))?(?:\+(?<build>[0-9A-Za-z-.]+))?$'
    $m = [regex]::Match($text, $pattern)
    if (-not $m.Success) {
        throw "Invalid semantic version: '$Version'. Expected MAJOR.MINOR.PATCH (e.g. 1.2.3)."
    }

    [pscustomobject]@{
        Major      = [int] $m.Groups['major'].Value
        Minor      = [int] $m.Groups['minor'].Value
        Patch      = [int] $m.Groups['patch'].Value
        Prerelease = $m.Groups['pre'].Value
        Build      = $m.Groups['build'].Value
        Prefix     = $m.Groups['prefix'].Value
        Original   = $text
    }
}

#endregion

#region Conventional commit parsing

# Matches a Conventional Commits header:  type(scope)!: description
# - type    : the change category (feat, fix, chore, ...)
# - scope   : optional, in parentheses
# - breaking: optional '!' immediately before the colon
$script:ConventionalCommitPattern =
    '^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]+)\))?(?<breaking>!)?:\s*(?<desc>.+)$'

function ConvertFrom-ConventionalCommit {
    <#
    .SYNOPSIS
        Parse a single commit message into its conventional-commit parts.
    .DESCRIPTION
        Returns a PSCustomObject with Type, Scope, Description and a Breaking
        flag. Breaking is true when the header uses the '!' marker OR when the
        message contains a 'BREAKING CHANGE' / 'BREAKING-CHANGE' token (the
        footer form). Messages that do not follow the convention are returned
        with Type = '' so callers can treat them as non-bumping "other" commits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Message
    )

    $first = ($Message -split "`r?`n", 2)[0].Trim()
    # The footer/body breaking marker may appear anywhere in the full message.
    $hasBreakingToken = $Message -match 'BREAKING[ -]CHANGE'

    $m = [regex]::Match($first, $script:ConventionalCommitPattern)
    if (-not $m.Success) {
        return [pscustomobject]@{
            Type        = ''
            Scope       = ''
            Description = $first
            Breaking    = [bool] $hasBreakingToken
            Raw         = $first
        }
    }

    [pscustomobject]@{
        Type        = $m.Groups['type'].Value.ToLowerInvariant()
        Scope       = $m.Groups['scope'].Value
        Description = $m.Groups['desc'].Value.Trim()
        Breaking    = ($m.Groups['breaking'].Value -eq '!') -or $hasBreakingToken
        Raw         = $first
    }
}

function Get-BumpType {
    <#
    .SYNOPSIS
        Determine the semantic-version bump level implied by a set of commits.
    .DESCRIPTION
        Applies Conventional Commits precedence over all supplied messages:
            breaking change  -> major
            feat             -> minor
            fix              -> patch
            anything else    -> none
        The highest-precedence result across every commit is returned, so a
        single breaking change outranks any number of feats or fixes.
    .OUTPUTS
        One of: 'major', 'minor', 'patch', 'none'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits
    )

    # Rank levels numerically so we can keep the maximum as we scan.
    $rank  = @{ none = 0; patch = 1; minor = 2; major = 3 }
    $level = 'none'

    foreach ($raw in $Commits) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $c = ConvertFrom-ConventionalCommit $raw

        $thisLevel =
            if ($c.Breaking)        { 'major' }
            elseif ($c.Type -eq 'feat') { 'minor' }
            elseif ($c.Type -eq 'fix')  { 'patch' }
            else                        { 'none'  }

        if ($rank[$thisLevel] -gt $rank[$level]) { $level = $thisLevel }
    }

    $level
}

#endregion

#region Version arithmetic

function Get-NextVersion {
    <#
    .SYNOPSIS
        Compute the next semantic version given a current version and a bump.
    .DESCRIPTION
        Standard SemVer increment rules:
            major -> (M+1).0.0
            minor -> M.(m+1).0
            patch -> M.m.(p+1)
            none  -> unchanged
        Any pre-release/build metadata is dropped on a real bump (the bumped
        version is a fresh release). A 'v' prefix on the input is preserved.
    .OUTPUTS
        The next version as a string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Current,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string] $BumpType
    )

    $v = ConvertTo-SemVer $Current

    switch ($BumpType) {
        'major' { $major = $v.Major + 1; $minor = 0;          $patch = 0 }
        'minor' { $major = $v.Major;     $minor = $v.Minor + 1; $patch = 0 }
        'patch' { $major = $v.Major;     $minor = $v.Minor;     $patch = $v.Patch + 1 }
        'none'  { return $v.Original }   # nothing changed: hand back the original text verbatim
    }

    "$($v.Prefix)$major.$minor.$patch"
}

#endregion

#region Version file I/O

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Read the current version from a version file or a package.json.
    .DESCRIPTION
        Detects JSON by extension: '*.json' files are parsed and the top-level
        "version" field is read; any other file is treated as plain text whose
        first non-empty line is the version. Returns an object carrying the raw
        Version string and the file Kind ('json' | 'text') so the writer can
        round-trip it in the same format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'."
    }

    if ([IO.Path]::GetExtension($Path) -ieq '.json') {
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }
        if (-not ($json.PSObject.Properties.Name -contains 'version') -or
            [string]::IsNullOrWhiteSpace([string] $json.version)) {
            throw "JSON file '$Path' has no `"version`" field."
        }
        $version = [string] $json.version
        $kind    = 'json'
    }
    else {
        # Plain text: first non-blank, non-comment line is the version.
        $line = Get-Content -LiteralPath $Path |
            Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } |
            Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw "Version file '$Path' is empty."
        }
        $version = $line.Trim()
        $kind    = 'text'
    }

    # Validate now so callers get a clear error at read time, not later.
    $null = ConvertTo-SemVer $version

    [pscustomobject]@{
        Path    = (Resolve-Path -LiteralPath $Path).Path
        Version = $version
        Kind    = $kind
    }
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Write a new version back into a version file, preserving its format.
    .DESCRIPTION
        For JSON files the "version" value is replaced with a targeted regex so
        formatting, key order and unrelated fields are left untouched. For plain
        text files the whole content is replaced with the new version (plus a
        trailing newline). The new version is validated before anything is
        written so a bad value cannot corrupt the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $NewVersion
    )

    $null = ConvertTo-SemVer $NewVersion   # fail fast on an invalid target

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'."
    }

    if ([IO.Path]::GetExtension($Path) -ieq '.json') {
        $content = Get-Content -LiteralPath $Path -Raw
        # Replace only the value of the first top-level "version": "..." pair.
        $pattern = '("version"\s*:\s*")[^"]*(")'
        if ($content -notmatch $pattern) {
            throw "JSON file '$Path' has no `"version`" field to update."
        }
        $updated = [regex]::Replace($content, $pattern, "`${1}$NewVersion`${2}", 1)
        Set-Content -LiteralPath $Path -Value $updated -NoNewline
    }
    else {
        Set-Content -LiteralPath $Path -Value $NewVersion
    }
}

#endregion

#region Changelog generation

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Build a markdown changelog entry for a release from its commits.
    .DESCRIPTION
        Groups commits into Breaking Changes, Features, Bug Fixes and Other
        Changes, in that order, following the "Keep a Changelog" style. Each
        line shows the optional scope in bold followed by the description.
        Empty sections are omitted entirely.
    .PARAMETER Date
        The release date string (e.g. '2026-06-27'). Defaults to today so the
        entry is deterministic in tests when supplied explicitly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Commits,

        [string] $Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    # Buckets in render order. The key order here is the section order on output.
    $sections = [ordered]@{
        'Breaking Changes' = New-Object System.Collections.Generic.List[string]
        'Features'         = New-Object System.Collections.Generic.List[string]
        'Bug Fixes'        = New-Object System.Collections.Generic.List[string]
        'Other Changes'    = New-Object System.Collections.Generic.List[string]
    }

    foreach ($raw in $Commits) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $c = ConvertFrom-ConventionalCommit $raw

        # Prefix the description with a bold scope when one is present.
        $line = if ($c.Scope) { "**$($c.Scope)**: $($c.Description)" } else { $c.Description }

        $bucket =
            if ($c.Breaking)            { 'Breaking Changes' }
            elseif ($c.Type -eq 'feat') { 'Features' }
            elseif ($c.Type -eq 'fix')  { 'Bug Fixes' }
            else                        { 'Other Changes' }

        $sections[$bucket].Add("- $line")
    }

    $sb = [System.Text.StringBuilder]::new()
    [void] $sb.AppendLine("## [$Version] - $Date")

    foreach ($name in $sections.Keys) {
        $items = $sections[$name]
        if ($items.Count -eq 0) { continue }   # skip empty sections
        [void] $sb.AppendLine()
        [void] $sb.AppendLine("### $name")
        foreach ($item in $items) { [void] $sb.AppendLine($item) }
    }

    $sb.ToString().TrimEnd() + "`n"
}

function Update-Changelog {
    <#
    .SYNOPSIS
        Prepend a new entry to a CHANGELOG.md file, creating it if needed.
    .DESCRIPTION
        Keeps a top-level '# Changelog' header at the very top and inserts the
        newest entry directly beneath it, above any previous entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Entry
    )

    $header = '# Changelog'

    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
    }
    else {
        $existing = "$header`n"
    }

    # Split the existing file into its header line and the body that follows so
    # the new entry slots in just under the header.
    if ($existing -match '(?s)^\s*#\s+Changelog\s*\r?\n(?<body>.*)$') {
        $body = $Matches['body'].TrimStart()
        $new  = "$header`n`n$Entry`n$body".TrimEnd() + "`n"
    }
    else {
        $new = "$header`n`n$Entry`n$($existing.TrimStart())".TrimEnd() + "`n"
    }

    Set-Content -LiteralPath $Path -Value $new -NoNewline
}

#endregion

#region Commit sources

function Get-CommitMessages {
    <#
    .SYNOPSIS
        Collect the commit messages that should drive the version bump.
    .DESCRIPTION
        Two interchangeable sources, in priority order:

        1. A commit-log fixture file (-CommitLogFile): one commit subject per
           line. Blank lines and lines beginning with '#' are ignored. This is
           the deterministic source used by the tests and the CI fixtures.

        2. Real git history (-RepositoryPath): commit subjects since the most
           recent tag (or the whole history when the repo has no tags). This is
           the source a live CI/CD pipeline would use.

        Returning a uniform string[] of subjects keeps every downstream
        consumer (Get-BumpType, New-ChangelogEntry) source-agnostic.
    #>
    [CmdletBinding()]
    param(
        [string] $CommitLogFile,
        [string] $RepositoryPath = '.'
    )

    if ($CommitLogFile) {
        if (-not (Test-Path -LiteralPath $CommitLogFile)) {
            throw "Commit log file not found: '$CommitLogFile'."
        }
        return @(
            Get-Content -LiteralPath $CommitLogFile |
                Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } |
                ForEach-Object { $_.Trim() }
        )
    }

    # Fall back to real git history. Limit to commits since the last tag when one
    # exists so a release only documents what is new.
    $range = $null
    try {
        $lastTag = (& git -C $RepositoryPath describe --tags --abbrev=0 2>$null)
        if ($LASTEXITCODE -eq 0 -and $lastTag) { $range = "$lastTag..HEAD" }
    }
    catch { $range = $null }

    $gitArgs = @('-C', $RepositoryPath, 'log', '--no-merges', '--pretty=format:%s')
    if ($range) { $gitArgs += $range }

    $output = & git @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read git history from '$RepositoryPath'. Provide -CommitLogFile instead."
    }

    return @($output | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

#endregion

#region Orchestration

function Resolve-VersionFile {
    <#
    .SYNOPSIS
        Pick the version file to operate on when one is not specified.
    .DESCRIPTION
        Searches a repository directory for a conventional version file, in
        priority order: version.txt, VERSION, then package.json. Returns the
        first that exists, or $null when none is found.
    #>
    [CmdletBinding()]
    param([string] $RepositoryPath = '.')

    foreach ($candidate in 'version.txt', 'VERSION', 'package.json') {
        $p = Join-Path $RepositoryPath $candidate
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Run the full bump: read version + commits, compute, write, changelog.
    .DESCRIPTION
        The end-to-end orchestrator. It reads the current version, determines
        the bump implied by the commits, computes the next version, and (unless
        the bump is 'none') writes the new version back and prepends a changelog
        entry. Returns a result object describing what happened; the caller (CLI
        / workflow) is responsible for surfacing it to the user.
    .OUTPUTS
        PSCustomObject with PreviousVersion, NewVersion, BumpType, CommitCount,
        Changed, VersionFile, ChangelogFile and ChangelogEntry.
    #>
    [CmdletBinding()]
    param(
        [string] $VersionFile,
        [string] $CommitLogFile,
        [string] $ChangelogFile = 'CHANGELOG.md',
        [string] $RepositoryPath = '.',
        [string] $Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    # 1. Resolve which version file to read (explicit, else auto-detect).
    if (-not $VersionFile) {
        $VersionFile = Resolve-VersionFile -RepositoryPath $RepositoryPath
        if (-not $VersionFile) {
            throw "No version file found in '$RepositoryPath' (looked for version.txt, VERSION, package.json) and none was specified."
        }
    }

    # 2. Read current version and the commits driving the release.
    $current  = Get-CurrentVersion -Path $VersionFile
    $commits  = Get-CommitMessages -CommitLogFile $CommitLogFile -RepositoryPath $RepositoryPath

    # 3. Decide the bump and the resulting version.
    $bumpType = Get-BumpType -Commits $commits
    $next     = Get-NextVersion -Current $current.Version -BumpType $bumpType

    $entry = $null
    $changed = $false
    if ($bumpType -ne 'none') {
        # 4. Persist the new version in its original file format.
        Update-VersionFile -Path $VersionFile -NewVersion $next

        # 5. Generate + prepend the changelog entry.
        $entry = New-ChangelogEntry -Version $next -Commits $commits -Date $Date
        Update-Changelog -Path $ChangelogFile -Entry $entry
        $changed = $true
    }

    [pscustomobject]@{
        PreviousVersion = $current.Version
        NewVersion      = $next
        BumpType        = $bumpType
        CommitCount     = $commits.Count
        Changed         = $changed
        VersionFile     = $VersionFile
        ChangelogFile   = $ChangelogFile
        ChangelogEntry  = $entry
    }
}

#endregion
