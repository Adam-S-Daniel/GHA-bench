<#
.SYNOPSIS
    Semantic version bumper driven by Conventional Commits.

.DESCRIPTION
    This file defines a small set of composable functions:

        Get-SemanticVersion   - read/parse a version from a file or string
        Get-CommitBumpType     - classify commits into major/minor/patch/none
        Get-NextVersion        - compute the next version given a bump type
        New-ChangelogEntry     - render a markdown changelog block
        Set-SemanticVersion    - write the new version back to disk
        Invoke-VersionBump     - orchestrate the whole flow

    The file is intentionally side-effect free when dot-sourced (it only
    *defines* functions), which makes it trivial to unit test with Pester:
    the test suite dot-sources this file and exercises each function in
    isolation. The CLI entry point lives in Invoke-Bump.ps1.

    Conventional Commit -> bump rules:
        breaking change ("!" marker or "BREAKING CHANGE" footer) -> major
        feat:                                                    -> minor
        fix:                                                     -> patch
        anything else                                            -> none
#>

Set-StrictMode -Version Latest

# Regex matching a semantic version anywhere in a string. Captures the three
# numeric components. An optional leading "v" is tolerated. Pre-release and
# build metadata are intentionally out of scope for this tool.
$script:SemVerRegex = '(?<![\d.])v?(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)'

function Get-SemanticVersion {
    <#
    .SYNOPSIS
        Parse a semantic version from a file (plain text or package.json) or
        from a raw string.

    .OUTPUTS
        A [pscustomobject] with integer Major/Minor/Patch properties and a
        ToString() that renders "Major.Minor.Patch".
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'InputString')]
        [string] $InputString
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Version file not found: '$Path'"
        }

        $raw = Get-Content -LiteralPath $Path -Raw

        # If this looks like JSON (package.json), prefer the structured
        # "version" field so we never accidentally match a version embedded
        # in a dependency range, etc.
        if ([System.IO.Path]::GetFileName($Path) -match '\.json$') {
            try {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "Failed to parse JSON in '$Path': $($_.Exception.Message)"
            }
            if (-not ($json.PSObject.Properties.Name -contains 'version') -or
                [string]::IsNullOrWhiteSpace([string]$json.version)) {
                throw "No valid semantic version found: '$Path' has no 'version' field."
            }
            $InputString = [string]$json.version
        } else {
            $InputString = $raw
        }
    }

    $match = [regex]::Match($InputString, $script:SemVerRegex)
    if (-not $match.Success) {
        throw "No valid semantic version found in input: '$($InputString.Trim())'"
    }

    return New-SemanticVersionObject `
        -Major ([int]$match.Groups['major'].Value) `
        -Minor ([int]$match.Groups['minor'].Value) `
        -Patch ([int]$match.Groups['patch'].Value)
}

function New-SemanticVersionObject {
    # Internal helper: builds the version object with a friendly ToString().
    param([int] $Major, [int] $Minor, [int] $Patch)

    $obj = [pscustomobject]@{
        Major = $Major
        Minor = $Minor
        Patch = $Patch
    }
    # Attach a ToString() so callers can interpolate the object directly.
    $obj | Add-Member -MemberType ScriptMethod -Name ToString -Force -Value {
        "$($this.Major).$($this.Minor).$($this.Patch)"
    }
    return $obj
}

function Get-CommitBumpType {
    <#
    .SYNOPSIS
        Determine the required bump type from a set of conventional commit
        messages.

    .DESCRIPTION
        Evaluates every commit and returns the highest-precedence bump:
        major > minor > patch > none. Commits may be supplied directly via
        -Commits or read from a fixture file via -Path (one commit line per
        line).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Commits')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Commits')]
        [AllowEmptyCollection()]
        [string[]] $Commits,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Commit log file not found: '$Path'"
        }
        # Read non-empty lines as individual commit messages.
        $Commits = Get-Content -LiteralPath $Path |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    # Precedence ranking so we can keep the maximum seen.
    $rank = @{ none = 0; patch = 1; minor = 2; major = 3 }
    $highest = 'none'

    foreach ($commit in $Commits) {
        $type = Get-SingleCommitBump -Message $commit
        if ($rank[$type] -gt $rank[$highest]) {
            $highest = $type
        }
    }

    return $highest
}

function Get-SingleCommitBump {
    # Classify one commit message. Internal helper for Get-CommitBumpType.
    param([string] $Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return 'none' }

    # A breaking change is signalled either by a "!" before the colon in the
    # type/scope prefix (e.g. "feat!:" or "fix(api)!:") or by a
    # "BREAKING CHANGE" / "BREAKING-CHANGE" token anywhere in the message.
    if ($Message -match '^[a-zA-Z]+(\([^)]*\))?!:' -or
        $Message -match 'BREAKING[ -]CHANGE') {
        return 'major'
    }
    if ($Message -match '^feat(\([^)]*\))?:') { return 'minor' }
    if ($Message -match '^fix(\([^)]*\))?:')  { return 'patch' }

    return 'none'
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Compute the next version object from a current version and bump type.
    #>
    param(
        [Parameter(Mandatory)] $Version,
        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string] $BumpType
    )

    switch ($BumpType) {
        'major' { return New-SemanticVersionObject -Major ($Version.Major + 1) -Minor 0 -Patch 0 }
        'minor' { return New-SemanticVersionObject -Major $Version.Major -Minor ($Version.Minor + 1) -Patch 0 }
        'patch' { return New-SemanticVersionObject -Major $Version.Major -Minor $Version.Minor -Patch ($Version.Patch + 1) }
        'none'  { return New-SemanticVersionObject -Major $Version.Major -Minor $Version.Minor -Patch $Version.Patch }
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Render a markdown changelog block for a release.

    .DESCRIPTION
        Groups commits into "Breaking Changes", "Features" and "Bug Fixes"
        sections (in that order). Empty sections are omitted. Other commit
        types are listed under "Other Changes" only if present.
    #>
    param(
        [Parameter(Mandatory)] [string]   $Version,
        [Parameter(Mandatory)] [string[]] $Commits,
        [string] $Date
    )

    if ([string]::IsNullOrWhiteSpace($Date)) {
        $Date = (Get-Date -Format 'yyyy-MM-dd')
    }

    $breaking = @()
    $features = @()
    $fixes    = @()
    $other    = @()

    foreach ($commit in $Commits) {
        if ([string]::IsNullOrWhiteSpace($commit)) { continue }

        # Pull a human-friendly description out of the conventional prefix.
        $desc = ($commit -replace '^[a-zA-Z]+(\([^)]*\))?!?:\s*', '').Trim()
        switch -Regex ($commit) {
            '^[a-zA-Z]+(\([^)]*\))?!:|BREAKING[ -]CHANGE' {
                # Strip a leading "BREAKING CHANGE:" footer label if present.
                $clean = ($commit -replace '^BREAKING[ -]CHANGE:\s*', '').Trim()
                $clean = ($clean -replace '^[a-zA-Z]+(\([^)]*\))?!?:\s*', '').Trim()
                $breaking += $clean
            }
            '^feat(\([^)]*\))?:' { $features += $desc }
            '^fix(\([^)]*\))?:'  { $fixes += $desc }
            default              { $other += $commit.Trim() }
        }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## [$Version] - $Date")
    [void]$sb.AppendLine()

    $appendSection = {
        param($title, $items)
        if ($items.Count -gt 0) {
            [void]$sb.AppendLine("### $title")
            foreach ($i in $items) { [void]$sb.AppendLine("- $i") }
            [void]$sb.AppendLine()
        }
    }

    & $appendSection 'BREAKING CHANGES' $breaking
    & $appendSection 'Features'         $features
    & $appendSection 'Bug Fixes'        $fixes
    & $appendSection 'Other Changes'    $other

    return $sb.ToString().TrimEnd() + "`n"
}

function Set-SemanticVersion {
    <#
    .SYNOPSIS
        Persist the new version back to the source file.

    .DESCRIPTION
        For package.json the "version" field is rewritten in place (other
        fields are preserved). For a plain version file the whole file is
        replaced with the new version string.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Cannot update version: file not found '$Path'"
    }

    if ([System.IO.Path]::GetFileName($Path) -match '\.json$') {
        $raw = Get-Content -LiteralPath $Path -Raw
        # Replace only the value of the "version" field, preserving formatting
        # and every other field. A targeted regex avoids round-tripping the
        # whole document (which would reorder/reformat it).
        $updated = [regex]::Replace(
            $raw,
            '("version"\s*:\s*")[^"]*(")',
            "`${1}$NewVersion`${2}",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        Set-Content -LiteralPath $Path -Value $updated -NoNewline
    } else {
        Set-Content -LiteralPath $Path -Value $NewVersion
    }
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        End-to-end version bump: read version + commits, compute the next
        version, update the version file and prepend a changelog entry.

    .OUTPUTS
        A [pscustomobject] with OldVersion, NewVersion, BumpType and
        ChangelogEntry properties.
    #>
    param(
        [Parameter(Mandatory)] [string] $VersionFile,
        [Parameter(Mandatory)] [string] $CommitLogFile,
        [string] $ChangelogFile,
        [string] $Date,
        # When set, treat "no bump-worthy commits" as a hard error instead of
        # a no-op. Useful in CI where an empty release is a mistake.
        [switch] $FailOnNoBump
    )

    $current  = Get-SemanticVersion -Path $VersionFile
    $bumpType = Get-CommitBumpType -Path $CommitLogFile

    if ($bumpType -eq 'none') {
        $msg = "No conventional commits found; no version bump is required."
        if ($FailOnNoBump) {
            throw "$msg (current version: $($current.ToString()))"
        }
        Write-Warning $msg
    }

    $next = Get-NextVersion -Version $current -BumpType $bumpType

    # Persist the new version (only if it actually changed).
    if ($bumpType -ne 'none') {
        Set-SemanticVersion -Path $VersionFile -NewVersion $next.ToString()
    }

    # Build and prepend the changelog entry.
    $commits = Get-Content -LiteralPath $CommitLogFile |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $entry = New-ChangelogEntry -Version $next.ToString() -Commits $commits -Date $Date

    if ($ChangelogFile) {
        $existing = ''
        if (Test-Path -LiteralPath $ChangelogFile) {
            $existing = Get-Content -LiteralPath $ChangelogFile -Raw
        }
        $header = "# Changelog`n`n"
        if ($existing -match '^\s*#\s*Changelog') {
            # Strip the old top-level header so we don't duplicate it.
            $existing = ($existing -replace '^\s*#\s*Changelog\s*\r?\n', '').TrimStart()
        }
        Set-Content -LiteralPath $ChangelogFile -Value ($header + $entry + "`n" + $existing).TrimEnd() -NoNewline
    }

    return [pscustomobject]@{
        OldVersion     = $current.ToString()
        NewVersion     = $next.ToString()
        BumpType       = $bumpType
        ChangelogEntry = $entry
    }
}
