<#
    VersionBumper.psm1

    Core logic for the semantic version bumper:
      - Reading the current version from a plain text VERSION file or a
        package.json file.
      - Writing the new version back to either kind of file.
      - Classifying conventional-commit messages into a semver bump type.
      - Computing the next version for a given bump type.
      - Generating a changelog entry from commit messages.

    The orchestration script (Invoke-VersionBump.ps1) wires these functions
    together; keeping them in a module makes each piece independently
    testable with Pester.
#>

Set-StrictMode -Version Latest

function Get-CurrentVersion {
    <#
        .SYNOPSIS
        Reads the current semantic version from a version file.

        .DESCRIPTION
        Supports two formats, selected by file extension:
          - *.json: parsed as JSON, version read from the top-level
            "version" property (e.g. package.json).
          - anything else: treated as a plain text file whose entire
            (trimmed) contents are the version string.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw

    if ($Path -match '\.json$') {
        try {
            $json = $raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }

        if (-not (Get-Member -InputObject $json -Name 'version' -MemberType NoteProperty)) {
            throw "Version file '$Path' has no 'version' field"
        }

        $version = [string]$json.version
    }
    else {
        $version = $raw.Trim()
    }

    if ($version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version '$version' in '$Path' is not a valid semantic version (expected X.Y.Z)"
    }

    return $version
}

function Get-NextVersion {
    <#
        .SYNOPSIS
        Computes the next semantic version for a given bump type.

        .DESCRIPTION
        major: X+1.0.0   minor: X.Y+1.0   patch: X.Y.Z+1
    #>
    param(
        [Parameter(Mandatory)]
        [string] $CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch')]
        [string] $BumpType
    )

    if ($CurrentVersion -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        throw "Version '$CurrentVersion' is not a valid semantic version (expected X.Y.Z)"
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    $patch = [int]$Matches.patch

    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
    }

    return "$major.$minor.$patch"
}

function Get-CommitMessagesFromFile {
    <#
        .SYNOPSIS
        Reads a mock commit log fixture: one commit message per non-blank line.

        .DESCRIPTION
        Simulates the output of `git log --pretty=%s` (or `%B` for a
        single-line message). Used both by unit tests and by any future
        caller that wants to feed an arbitrary commit log file into the
        bump-type classifier.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Commit log file not found: '$Path'"
    }

    # The leading comma prevents PowerShell from enumerating the array onto
    # the output stream (which would silently unwrap a single-element
    # result into a bare string at the caller).
    return , @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -ne '' })
}

function Get-BumpType {
    <#
        .SYNOPSIS
        Classifies a set of conventional-commit messages into a semver bump type.

        .DESCRIPTION
        Rules (highest priority wins when multiple commit types are present):
          - major: a "!" breaking marker right before the colon (e.g. "feat!:"),
                    or a "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer anywhere
                    in the message.
          - minor: a "feat:" (or "feat(scope):") commit.
          - patch: a "fix:" (or "fix(scope):") commit.

        Commit types that don't affect the version (chore, docs, test, etc.)
        are ignored. Returns $null when no commit affects the version.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $CommitMessages
    )

    $hasMajor = $false
    $hasMinor = $false
    $hasPatch = $false

    foreach ($message in $CommitMessages) {
        if ([string]::IsNullOrWhiteSpace($message)) { continue }
        $trimmed = $message.Trim()

        if ($trimmed -match '^\w+(\([^)]*\))?!:' -or $trimmed -match 'BREAKING[ -]CHANGE:') {
            $hasMajor = $true
        }
        elseif ($trimmed -match '^feat(\([^)]*\))?:') {
            $hasMinor = $true
        }
        elseif ($trimmed -match '^fix(\([^)]*\))?:') {
            $hasPatch = $true
        }
    }

    if ($hasMajor) { return 'major' }
    if ($hasMinor) { return 'minor' }
    if ($hasPatch) { return 'patch' }
    return $null
}

function Update-VersionFile {
    <#
        .SYNOPSIS
        Writes a new version into a version file, mirroring the format
        Get-CurrentVersion read it in (plain text vs. package.json).
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Version file not found: '$Path'"
    }

    if ($Path -match '\.json$') {
        try {
            $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON version file '$Path': $($_.Exception.Message)"
        }

        $json.version = $NewVersion
        ($json | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Path -NoNewline
    }
    else {
        Set-Content -LiteralPath $Path -Value $NewVersion -NoNewline
    }
}

function New-ChangelogEntry {
    <#
        .SYNOPSIS
        Builds a Markdown changelog entry for a new version from a set of
        conventional-commit messages, grouped into Breaking Changes,
        Features, and Bug Fixes sections (only sections with content are
        included).
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $CommitMessages,

        [string] $Date = (Get-Date -Format 'yyyy-MM-dd')
    )

    $breaking = [System.Collections.Generic.List[string]]::new()
    $features = [System.Collections.Generic.List[string]]::new()
    $fixes = [System.Collections.Generic.List[string]]::new()

    foreach ($message in $CommitMessages) {
        if ([string]::IsNullOrWhiteSpace($message)) { continue }
        $trimmed = $message.Trim()

        if ($trimmed -match '^\w+(\([^)]*\))?!:\s*(?<desc>.+)') {
            $breaking.Add($Matches.desc)
        }
        elseif ($trimmed -match 'BREAKING[ -]CHANGE:\s*(?<desc>.+)') {
            $breaking.Add($Matches.desc)
        }
        elseif ($trimmed -match '^feat(\([^)]*\))?:\s*(?<desc>.+)') {
            $features.Add($Matches.desc)
        }
        elseif ($trimmed -match '^fix(\([^)]*\))?:\s*(?<desc>.+)') {
            $fixes.Add($Matches.desc)
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("## [$Version] - $Date")

    if ($breaking.Count -gt 0) {
        $lines.Add('')
        $lines.Add('### Breaking Changes')
        foreach ($item in $breaking) { $lines.Add("- $item") }
    }
    if ($features.Count -gt 0) {
        $lines.Add('')
        $lines.Add('### Features')
        foreach ($item in $features) { $lines.Add("- $item") }
    }
    if ($fixes.Count -gt 0) {
        $lines.Add('')
        $lines.Add('### Bug Fixes')
        foreach ($item in $fixes) { $lines.Add("- $item") }
    }

    return ($lines -join "`n")
}

function Add-ChangelogEntry {
    <#
        .SYNOPSIS
        Prepends a changelog entry to a CHANGELOG.md file, creating the
        file (with a top-level "# Changelog" header) if it doesn't exist.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Entry
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = Get-Content -LiteralPath $Path -Raw
        $header = '# Changelog'
        if ($existing -match '^\s*# Changelog\s*\r?\n') {
            $body = $existing -replace '^\s*# Changelog\s*\r?\n', ''
        }
        else {
            $body = $existing
        }
        $body = $body.TrimStart("`r", "`n")
        $newContent = "$header`n`n$Entry`n`n$body".TrimEnd() + "`n"
    }
    else {
        $newContent = "# Changelog`n`n$Entry`n"
    }

    Set-Content -LiteralPath $Path -Value $newContent -NoNewline
}

function Get-CommitMessagesFromGit {
    <#
        .SYNOPSIS
        Reads full commit messages (subject + body) from the real git
        history of the current repository.

        .DESCRIPTION
        Defaults to every commit since the most recent annotated/lightweight
        tag (or the entire history if no tag exists). Reading the full body
        (not just the subject) ensures "BREAKING CHANGE:" footers are seen
        by Get-BumpType.
    #>
    param(
        [string] $Range
    )

    if (-not $Range) {
        $lastTag = git describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0 -and $lastTag) {
            $Range = "$lastTag..HEAD"
        }
        else {
            $Range = 'HEAD'
        }
    }

    # %x1e (record separator) delimits one commit's full message from the next.
    # PowerShell captures multi-line external-command output as a string
    # array (one element per line) -- or a lone scalar string when there's
    # only one line -- so we funnel it through Out-String to reliably get
    # back a single string with the original newlines intact before
    # splitting on the record separator. (Naively `-join`-ing a possibly-
    # scalar value is unsafe: -join on a bare string iterates characters.)
    $recordSeparator = [char]0x1e
    $rawLines = git log $Range "--pretty=format:%B$recordSeparator" 2>$null
    $gitExitCode = $LASTEXITCODE

    if ($gitExitCode -ne 0 -or -not $rawLines) {
        return , @()
    }

    $raw = ($rawLines | Out-String)

    # The leading comma prevents PowerShell from enumerating the array onto
    # the output stream (which would silently unwrap a single-commit
    # result into a bare string at the caller).
    return , @(
        ($raw -split $recordSeparator) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

Export-ModuleMember -Function Get-CurrentVersion, Get-NextVersion, Get-CommitMessagesFromFile, Get-BumpType, Update-VersionFile, New-ChangelogEntry, Add-ChangelogEntry, Get-CommitMessagesFromGit
