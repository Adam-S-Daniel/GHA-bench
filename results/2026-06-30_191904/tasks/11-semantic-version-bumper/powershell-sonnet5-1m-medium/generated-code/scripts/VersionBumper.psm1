# VersionBumper.psm1
# Semantic version bumper: parses a version from version.json/package.json,
# inspects conventional commit messages to decide the next version, updates
# the version file, and produces a changelog entry.

function Get-CurrentVersion {
    <#
        .SYNOPSIS
        Reads a semantic version string out of a version.json or package.json file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'"
    }

    $content = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    if (-not $content.PSObject.Properties['version'] -or [string]::IsNullOrWhiteSpace($content.version)) {
        throw "No 'version' field found in file: '$Path'"
    }

    return $content.version
}

function Get-CommitMessages {
    <#
        .SYNOPSIS
        Reads a mock commit log fixture and splits it into individual commit
        messages. Commits are separated by a line containing only '%%%'.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Commit log file not found: '$Path'"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $messages = [regex]::Split($raw, '(?m)^%%%\s*$') | ForEach-Object { $_.Trim() }

    return @($messages | Where-Object { $_ -ne '' })
}

function Get-CommitBumpType {
    <#
        .SYNOPSIS
        Classifies a set of conventional commit messages into a semver bump
        type: 'major' (breaking change), 'minor' (feat), 'patch' (fix), or
        'none' (no release-worthy commits).
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Messages
    )

    if (-not $Messages -or $Messages.Count -eq 0) {
        throw 'No commit messages were supplied to classify.'
    }

    $hasBreaking = $false
    $hasFeat = $false
    $hasFix = $false

    foreach ($message in $Messages) {
        if ($message -match '(?m)^BREAKING CHANGE:' -or $message -match '^\w+(\([^)]*\))?!:') {
            $hasBreaking = $true
        }
        elseif ($message -match '^feat(\([^)]*\))?:') {
            $hasFeat = $true
        }
        elseif ($message -match '^fix(\([^)]*\))?:') {
            $hasFix = $true
        }
    }

    if ($hasBreaking) { return 'major' }
    if ($hasFeat) { return 'minor' }
    if ($hasFix) { return 'patch' }
    return 'none'
}

function Get-NextVersion {
    <#
        .SYNOPSIS
        Computes the next semantic version given a current 'major.minor.patch'
        version string and a bump type of 'major', 'minor', 'patch', or 'none'.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [ValidateSet('major', 'minor', 'patch', 'none')]
        [string]$BumpType
    )

    if ($CurrentVersion -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        throw "Current version '$CurrentVersion' is not a valid semantic version (expected major.minor.patch)."
    }

    $major = [int]$Matches.major
    $minor = [int]$Matches.minor
    $patch = [int]$Matches.patch

    switch ($BumpType) {
        'major' { return "$($major + 1).0.0" }
        'minor' { return "$major.$($minor + 1).0" }
        'patch' { return "$major.$minor.$($patch + 1)" }
        'none'  { return "$major.$minor.$patch" }
    }
}

function Update-VersionFile {
    <#
        .SYNOPSIS
        Rewrites the 'version' field of a version.json/package.json file in
        place, preserving all other fields and key ordering.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NewVersion
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Version file not found: '$Path'"
    }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $json['version'] = $NewVersion
    ($json | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $Path -NoNewline
}

function New-ChangelogEntry {
    <#
        .SYNOPSIS
        Builds a Keep a Changelog style entry, grouping commit subjects under
        Breaking Changes / Features / Fixes headings.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$Date,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Messages
    )

    $breaking = @()
    $features = @()
    $fixes = @()

    foreach ($message in $Messages) {
        $subject = ($message -split "`n")[0]

        if ($message -match '(?m)^BREAKING CHANGE:' -or $subject -match '^\w+(\([^)]*\))?!:') {
            $breaking += ($subject -replace '^(\w+)(\([^)]*\))?!?:\s*', '')
        }
        elseif ($subject -match '^feat(\([^)]*\))?:') {
            $features += ($subject -replace '^feat(\([^)]*\))?:\s*', '')
        }
        elseif ($subject -match '^fix(\([^)]*\))?:') {
            $fixes += ($subject -replace '^fix(\([^)]*\))?:\s*', '')
        }
    }

    $lines = @("## [$Version] - $Date", '')

    if ($breaking.Count -gt 0) {
        $lines += '### Breaking Changes'
        $lines += ($breaking | ForEach-Object { "- $_" })
        $lines += ''
    }
    if ($features.Count -gt 0) {
        $lines += '### Features'
        $lines += ($features | ForEach-Object { "- $_" })
        $lines += ''
    }
    if ($fixes.Count -gt 0) {
        $lines += '### Fixes'
        $lines += ($fixes | ForEach-Object { "- $_" })
        $lines += ''
    }
    if ($breaking.Count -eq 0 -and $features.Count -eq 0 -and $fixes.Count -eq 0) {
        $lines += 'No notable changes.'
        $lines += ''
    }

    return ($lines -join "`n").TrimEnd() + "`n"
}

function Invoke-VersionBump {
    <#
        .SYNOPSIS
        Orchestrates a full semantic version bump: reads the current version,
        classifies the commit log, computes and writes the next version, and
        prepends a changelog entry describing the release.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$VersionFilePath,

        [Parameter(Mandatory)]
        [string]$CommitLogPath,

        [Parameter(Mandatory)]
        [string]$ChangelogPath,

        [Parameter(Mandatory)]
        [string]$Date
    )

    $oldVersion = Get-CurrentVersion -Path $VersionFilePath
    $messages = Get-CommitMessages -Path $CommitLogPath
    $bumpType = Get-CommitBumpType -Messages $messages
    $newVersion = Get-NextVersion -CurrentVersion $oldVersion -BumpType $bumpType

    if ($bumpType -ne 'none') {
        Update-VersionFile -Path $VersionFilePath -NewVersion $newVersion
    }

    $entry = New-ChangelogEntry -Version $newVersion -Date $Date -Messages $messages

    $existingChangelog = ''
    if (Test-Path -LiteralPath $ChangelogPath) {
        $existingChangelog = Get-Content -LiteralPath $ChangelogPath -Raw
    }
    Set-Content -LiteralPath $ChangelogPath -Value ($entry + "`n" + $existingChangelog).TrimEnd() -NoNewline

    return [pscustomobject]@{
        OldVersion = $oldVersion
        NewVersion = $newVersion
        BumpType   = $bumpType
    }
}

Export-ModuleMember -Function Get-CurrentVersion, Get-CommitMessages, Get-CommitBumpType, Get-NextVersion, Update-VersionFile, New-ChangelogEntry, Invoke-VersionBump
