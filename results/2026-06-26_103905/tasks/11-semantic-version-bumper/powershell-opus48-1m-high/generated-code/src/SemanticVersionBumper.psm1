#
# SemanticVersionBumper.psm1
#
# A small, dependency-free PowerShell module that:
#   * reads a semantic version from a plain VERSION file or a package.json
#   * inspects conventional-commit messages to decide the bump type
#   * computes the next version (feat -> minor, fix -> patch, breaking -> major)
#   * writes the new version back to the file
#   * renders a Keep-a-Changelog style entry from the commits
#
# Built incrementally with red/green TDD (see tests/SemanticVersionBumper.Tests.ps1).
#

Set-StrictMode -Version Latest

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Reads the current semantic version from a version file.
    .DESCRIPTION
        Supports two file shapes:
          * package.json  -> the value of the top-level "version" property
          * anything else -> the trimmed file contents (a bare version string)
        A leading "v" (e.g. "v1.2.3") is accepted and stripped.
    .PARAMETER Path
        Path to the version file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    # package.json gets JSON-aware handling; everything else is a bare string.
    if ([System.IO.Path]::GetFileName($Path) -ieq 'package.json') {
        $raw = Get-Content -Path $Path -Raw
        $json = $raw | ConvertFrom-Json
        if (-not $json.PSObject.Properties.Name.Contains('version')) {
            throw "package.json at '$Path' has no 'version' property."
        }
        $version = [string]$json.version
    }
    else {
        $version = (Get-Content -Path $Path -Raw).Trim()
    }

    # Normalise an optional leading "v".
    return ($version -replace '^[vV]', '')
}

function Get-CommitsFromLog {
    <#
    .SYNOPSIS
        Parses a commit log fixture into structured commit objects.
    .DESCRIPTION
        The expected format is one commit per line: "<hash> <subject>", which is
        exactly what `git log --pretty=format:"%h %s"` emits. Blank lines and
        lines beginning with '#' (comments) are ignored. Each returned object has
        a .Hash and a .Subject property.
    .PARAMETER Path
        Path to the commit log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Commit log file not found: '$Path'"
    }

    $commits = [System.Collections.Generic.List[object]]::new()

    foreach ($line in (Get-Content -Path $Path)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }   # skip blanks
        if ($trimmed.StartsWith('#')) { continue }                 # skip comments

        # Split into hash + remaining subject on the first run of whitespace.
        $parts = $trimmed -split '\s+', 2
        if ($parts.Count -lt 2) {
            throw "Malformed commit line (expected '<hash> <subject>'): '$line'"
        }

        $commits.Add([pscustomobject]@{
            Hash    = $parts[0]
            Subject = $parts[1]
        })
    }

    # Emit the commits. Callers should wrap in @(...) when they need .Count,
    # since PowerShell unrolls 0- and 1-element results on return.
    return $commits.ToArray()
}

function Get-BumpType {
    <#
    .SYNOPSIS
        Determines the semantic-version bump kind from commit subjects.
    .DESCRIPTION
        Applies conventional-commits rules with precedence major > minor > patch:
          * a breaking change  -> 'major'  (a "!" before the colon, e.g. "feat!:"
                                   or "feat(api)!:", or a "BREAKING CHANGE" token)
          * a "feat" commit    -> 'minor'
          * a "fix" commit     -> 'patch'
          * anything else      -> contributes nothing
        Returns 'none' when no commit warrants a bump.
    .PARAMETER Subjects
        One or more commit subject lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Subjects
    )

    $bump = 'none'

    foreach ($subject in $Subjects) {
        if ([string]::IsNullOrWhiteSpace($subject)) { continue }

        # Breaking change wins immediately — nothing ranks higher than 'major'.
        # Matches a "!" right before the colon in the type/scope prefix, or the
        # conventional "BREAKING CHANGE" / "BREAKING-CHANGE" footer token.
        if ($subject -match '^[a-zA-Z]+(\([^)]*\))?!:' -or
            $subject -match 'BREAKING[ -]CHANGE') {
            return 'major'
        }

        # feat: ... (optionally scoped) -> at least a minor bump.
        if ($subject -match '^feat(\([^)]*\))?:') {
            $bump = 'minor'
            continue
        }

        # fix: ... (optionally scoped) -> at least a patch bump, but never
        # downgrade an already-decided minor.
        if ($subject -match '^fix(\([^)]*\))?:') {
            if ($bump -ne 'minor') { $bump = 'patch' }
            continue
        }
    }

    return $bump
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version from a current version and bump type.
    .DESCRIPTION
        major -> X+1.0.0, minor -> X.Y+1.0, patch -> X.Y.Z+1, none -> unchanged.
    .PARAMETER CurrentVersion
        The current version, e.g. "1.2.3".
    .PARAMETER BumpType
        One of major, minor, patch, none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    # Parse strictly into the three numeric components.
    if ($CurrentVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "'$CurrentVersion' is not a valid semantic version (expected MAJOR.MINOR.PATCH)."
    }

    [int]$major = $Matches[1]
    [int]$minor = $Matches[2]
    [int]$patch = $Matches[3]

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { }   # leave the version untouched
    }

    return "$major.$minor.$patch"
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Writes a new version back to the version file.
    .DESCRIPTION
        For package.json the JSON is parsed, only the "version" property is
        replaced, and the file is re-serialised (other fields preserved). For a
        plain file the contents are replaced with the bare version string.
    .PARAMETER Path
        Path to the version file to update.
    .PARAMETER NewVersion
        The new version string to write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    if ([System.IO.Path]::GetFileName($Path) -ieq 'package.json') {
        $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
        $json.version = $NewVersion
        # Depth 100 keeps deeply nested package.json structures intact.
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $Path
    }
    else {
        Set-Content -Path $Path -Value $NewVersion -NoNewline
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Renders a Keep-a-Changelog style entry for a release.
    .DESCRIPTION
        Groups commits into BREAKING CHANGES / Features / Bug Fixes sections
        (by conventional-commit precedence) and lists each as
        "- <description> (<hash>)". Commits that don't map to a section (chore,
        docs, style, ...) are omitted. Empty sections are not rendered.
    .PARAMETER Version
        The version being released, e.g. "2.0.0".
    .PARAMETER Commits
        Commit objects with .Hash and .Subject properties.
    .PARAMETER Date
        Release date string (defaults to today, yyyy-MM-dd).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Commits,

        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    # Buckets for the three changelog sections.
    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes    = [System.Collections.Generic.List[string]]::new()

    foreach ($commit in $Commits) {
        $subject = [string]$commit.Subject
        # Decompose "type(scope)!: description" into its parts.
        if ($subject -notmatch '^(?<type>[a-zA-Z]+)(\((?<scope>[^)]*)\))?(?<bang>!)?:\s*(?<desc>.*)$') {
            continue   # not a conventional commit -> not changelog-worthy
        }

        $type  = $Matches['type'].ToLower()
        $scope = $Matches['scope']
        $bang  = $Matches['bang']
        $desc  = $Matches['desc'].Trim()

        # Re-attach the scope as a readable prefix, e.g. "ui: button alignment".
        if ($scope) { $desc = "${scope}: $desc" }

        $line = "- $desc ($($commit.Hash))"

        # Precedence: breaking first, then feat, then fix; ignore everything else.
        if ($bang -or $subject -match 'BREAKING[ -]CHANGE') {
            $breaking.Add($line)
        }
        elseif ($type -eq 'feat') {
            $features.Add($line)
        }
        elseif ($type -eq 'fix') {
            $fixes.Add($line)
        }
    }

    # Assemble the entry, only emitting sections that have content.
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## [$Version] - $Date")

    $sections = @(
        @{ Title = '### ⚠ BREAKING CHANGES'; Items = $breaking }
        @{ Title = '### Features';            Items = $features }
        @{ Title = '### Bug Fixes';           Items = $fixes }
    )

    foreach ($section in $sections) {
        if ($section.Items.Count -gt 0) {
            [void]$sb.AppendLine()
            [void]$sb.AppendLine($section.Title)
            foreach ($item in $section.Items) {
                [void]$sb.AppendLine($item)
            }
        }
    }

    return $sb.ToString().TrimEnd() + "`n"
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Orchestrates a full semantic-version bump from a commit log.
    .DESCRIPTION
        Reads the current version, parses the commit log, decides the bump type,
        and — when a bump is warranted — updates the version file and prepends a
        changelog entry. Returns a result object describing the outcome.
    .PARAMETER VersionFile
        Path to the VERSION file or package.json.
    .PARAMETER CommitLog
        Path to the commit log fixture ("<hash> <subject>" per line).
    .PARAMETER ChangelogFile
        Path to the changelog to update/create (default CHANGELOG.md).
    .PARAMETER Date
        Release date for the changelog entry (default today).
    .OUTPUTS
        PSCustomObject with PreviousVersion, NewVersion, BumpType, Bumped,
        CommitCount and ChangelogEntry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionFile,

        [Parameter(Mandatory)]
        [string]$CommitLog,

        [string]$ChangelogFile = 'CHANGELOG.md',

        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    # 1. Read inputs.
    $currentVersion = Get-CurrentVersion -Path $VersionFile
    $commits        = @(Get-CommitsFromLog -Path $CommitLog)

    # 2. Decide the bump.
    $subjects = @($commits | ForEach-Object { $_.Subject })
    $bumpType = Get-BumpType -Subjects $subjects
    $newVersion = Get-NextVersion -CurrentVersion $currentVersion -BumpType $bumpType

    $result = [pscustomobject]@{
        PreviousVersion = $currentVersion
        NewVersion      = $newVersion
        BumpType        = $bumpType
        Bumped          = ($bumpType -ne 'none')
        CommitCount     = $commits.Count
        ChangelogEntry  = ''
    }

    # 3. No qualifying commits -> leave everything untouched.
    if (-not $result.Bumped) {
        return $result
    }

    # 4. Apply changes: bump the version file and prepend the changelog entry.
    Update-VersionFile -Path $VersionFile -NewVersion $newVersion

    $entry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date
    $result.ChangelogEntry = $entry

    if (Test-Path -Path $ChangelogFile -PathType Leaf) {
        # Insert the new entry directly beneath the "# Changelog" title if present,
        # otherwise prepend it to keep the newest release at the top.
        $existing = Get-Content -Path $ChangelogFile -Raw
        $header = "# Changelog`n"
        if ($existing.StartsWith('# Changelog')) {
            $rest = $existing.Substring($existing.IndexOf("`n") + 1).TrimStart("`r", "`n")
            $content = "$header`n$entry`n$rest"
        }
        else {
            $content = "$header`n$entry`n$existing"
        }
        Set-Content -Path $ChangelogFile -Value $content
    }
    else {
        Set-Content -Path $ChangelogFile -Value "# Changelog`n`n$entry"
    }

    return $result
}

# Export the public surface of the module.
Export-ModuleMember -Function @(
    'Get-CurrentVersion',
    'Get-CommitsFromLog',
    'Get-BumpType',
    'Get-NextVersion',
    'Update-VersionFile',
    'New-ChangelogEntry',
    'Invoke-VersionBump'
)
