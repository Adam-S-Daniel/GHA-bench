# VersionBumper.psm1
#
# Core logic for the semantic version bumper tool. Pure, testable functions
# only -- no console I/O or environment-specific side effects live here.
# The CLI wiring (argument handling, GITHUB_OUTPUT, console messages) lives
# in scripts/Invoke-SemanticVersionBumper.ps1, which imports this module.

Set-StrictMode -Version Latest

function Get-VersionFromFile {
    <#
    .SYNOPSIS
        Reads a semantic version string from a VERSION file or a
        package.json file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    $raw = Get-Content -Path $Path -Raw

    if ($Path -match '\.json$') {
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Failed to parse '$Path' as JSON: $($_.Exception.Message)"
        }

        if (-not (Get-Member -InputObject $json -Name 'version' -MemberType NoteProperty)) {
            throw "No 'version' field found in JSON file '$Path'"
        }

        return [string]$json.version
    }

    $version = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Version file '$Path' is empty"
    }

    return $version
}

function Get-CommitMessages {
    <#
    .SYNOPSIS
        Returns the list of commit subject lines to analyze.

    .DESCRIPTION
        When -Path is supplied, reads commit subjects from a plain-text log
        file (one subject per line -- this is the shape produced by
        `git log --pretty=format:%s` and is how the mock commit-log
        fixtures used in tests are structured). Blank lines are ignored.

        When -Path is omitted, falls back to real `git log` output since the
        most recent tag (or full history if no tag exists), which is what
        the tool uses outside of tests.
    #>
    param(
        [Parameter()]
        [string]$Path
    )

    if ($Path) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "Commit log file not found: '$Path'"
        }
        $lines = Get-Content -Path $Path
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'git is not available on PATH and no -Path fixture was supplied'
        }

        $lastTag = git describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0 -and $lastTag) {
            $lines = git log "$lastTag..HEAD" --pretty=format:%s 2>$null
        } else {
            $lines = git log --pretty=format:%s 2>$null
        }

        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to read commit history via git log'
        }
    }

    return @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

function Get-BumpType {
    <#
    .SYNOPSIS
        Classifies a set of conventional-commit messages into the semver
        bump they imply: Major, Minor, Patch, or None.

    .DESCRIPTION
        Rules (evaluated in priority order, highest wins):
          Major - a "!" breaking marker right before the colon
                  (e.g. "feat!: ..." or "fix(api)!: ...") or a line
                  containing "BREAKING CHANGE".
          Minor - a "feat:" or "feat(scope):" commit.
          Patch - a "fix:" or "fix(scope):" commit.
          None  - nothing conventional matched (e.g. only "chore:"/"docs:").
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Messages
    )

    $hasBreaking = $Messages | Where-Object {
        $_ -match '^\w+(\([^)]*\))?!:' -or $_ -match 'BREAKING CHANGE'
    }
    if ($hasBreaking) { return 'Major' }

    $hasFeat = $Messages | Where-Object { $_ -match '^feat(\([^)]*\))?:' }
    if ($hasFeat) { return 'Minor' }

    $hasFix = $Messages | Where-Object { $_ -match '^fix(\([^)]*\))?:' }
    if ($hasFix) { return 'Patch' }

    return 'None'
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next semantic version given a current MAJOR.MINOR.PATCH
        version and a bump type produced by Get-BumpType.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateSet('Major', 'Minor', 'Patch', 'None')]
        [string]$BumpType
    )

    if ($CurrentVersion -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        throw "'$CurrentVersion' is not a valid semantic version (expected MAJOR.MINOR.PATCH)"
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    $patch = [int]$Matches.patch

    switch ($BumpType) {
        'Major' { return "$($major + 1).0.0" }
        'Minor' { return "$major.$($minor + 1).0" }
        'Patch' { return "$major.$minor.$($patch + 1)" }
        'None'  { return "$major.$minor.$patch" }
    }
}

function New-ChangelogEntry {
    <#
    .SYNOPSIS
        Builds a Markdown changelog section for a new version, grouping the
        given conventional-commit messages into Breaking Changes / Features
        / Fixes / Other subsections. Empty subsections are omitted.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Messages,

        [Parameter()]
        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes = [System.Collections.Generic.List[string]]::new()
    $other = [System.Collections.Generic.List[string]]::new()

    foreach ($message in $Messages) {
        if ($message -match 'BREAKING CHANGE:\s*(?<desc>.+)$') {
            $breaking.Add($Matches.desc.Trim())
        } elseif ($message -match '^\w+(\([^)]*\))?!:\s*(?<desc>.+)$') {
            $breaking.Add($Matches.desc.Trim())
        } elseif ($message -match '^feat(\([^)]*\))?:\s*(?<desc>.+)$') {
            $features.Add($Matches.desc.Trim())
        } elseif ($message -match '^fix(\([^)]*\))?:\s*(?<desc>.+)$') {
            $fixes.Add($Matches.desc.Trim())
        } else {
            $other.Add($message.Trim())
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")

    $sections = @(
        @{ Title = 'Breaking Changes'; Items = $breaking }
        @{ Title = 'Features'; Items = $features }
        @{ Title = 'Fixes'; Items = $fixes }
        @{ Title = 'Other'; Items = $other }
    )

    foreach ($section in $sections) {
        if ($section.Items.Count -eq 0) { continue }
        $lines.Add('')
        $lines.Add("### $($section.Title)")
        foreach ($item in $section.Items) {
            $lines.Add("- $item")
        }
    }

    return ($lines -join "`n")
}

function Update-VersionFile {
    <#
    .SYNOPSIS
        Writes a new version into a VERSION file or package.json file.

    .DESCRIPTION
        For package.json, only the "version" field's value is replaced via
        a targeted regex substitution on the raw text, so the rest of the
        file (formatting, key order, other fields) is left untouched.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    if ($Path -match '\.json$') {
        $raw = Get-Content -Path $Path -Raw
        $pattern = '"version"\s*:\s*"[^"]*"'
        if ($raw -notmatch $pattern) {
            throw "No 'version' field found in JSON file '$Path'"
        }
        $updated = [regex]::Replace($raw, $pattern, "`"version`": `"$NewVersion`"", 1)
        Set-Content -Path $Path -Value $updated -NoNewline
        return
    }

    Set-Content -Path $Path -Value $NewVersion -NoNewline
}

function Update-ChangelogFile {
    <#
    .SYNOPSIS
        Prepends a changelog entry (as produced by New-ChangelogEntry) to a
        CHANGELOG.md file, creating it with a top-level title if it does not
        already exist.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Entry
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $existing = Get-Content -Path $Path -Raw
        $body = "$Entry`n`n$existing"
    } else {
        $body = "# Changelog`n`n$Entry`n"
    }

    Set-Content -Path $Path -Value $body -NoNewline
}

function Invoke-VersionBump {
    <#
    .SYNOPSIS
        Orchestrates the full semantic-version-bump pipeline: read the
        current version, classify commits since the last release, compute
        the next version, update the version file, and prepend a changelog
        entry.

    .DESCRIPTION
        This is the single entry point the CLI script wraps. It is also
        exactly what a caller who wants "just do the bump" would call.

    .OUTPUTS
        A PSCustomObject with OldVersion, NewVersion, BumpType, and
        ChangelogEntry properties.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$VersionFilePath,

        [Parameter()]
        [string]$CommitLogPath,

        [Parameter(Mandatory)]
        [string]$ChangelogFilePath,

        [Parameter()]
        [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    $oldVersion = Get-VersionFromFile -Path $VersionFilePath
    $messages = Get-CommitMessages -Path $CommitLogPath
    $bumpType = Get-BumpType -Messages $messages

    if ($bumpType -eq 'None') {
        throw "No version-relevant commits found (looked for feat/fix/BREAKING CHANGE markers in $($messages.Count) commit message(s)); nothing to release"
    }

    $newVersion = Get-NextVersion -CurrentVersion $oldVersion -BumpType $bumpType
    $entry = New-ChangelogEntry -Version $newVersion -Messages $messages -Date $Date

    Update-VersionFile -Path $VersionFilePath -NewVersion $newVersion
    Update-ChangelogFile -Path $ChangelogFilePath -Entry $entry

    return [PSCustomObject]@{
        OldVersion      = $oldVersion
        NewVersion      = $newVersion
        BumpType        = $bumpType
        ChangelogEntry  = $entry
    }
}

Export-ModuleMember -Function Get-VersionFromFile, Get-CommitMessages, Get-BumpType, Get-NextVersion, New-ChangelogEntry, Update-VersionFile, Update-ChangelogFile, Invoke-VersionBump
