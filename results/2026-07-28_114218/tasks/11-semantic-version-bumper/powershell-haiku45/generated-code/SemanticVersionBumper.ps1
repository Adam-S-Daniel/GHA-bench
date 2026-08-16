# SemanticVersionBumper - Parse versions, bump based on commit types, generate changelog
# Implements conventional commit parsing and semantic versioning logic

<#
.SYNOPSIS
    Parse semantic version from JSON content (typically package.json)

.PARAMETER JsonContent
    JSON string containing a version field

.OUTPUTS
    String: semantic version (e.g., "1.2.3")
#>
function ParseVersion {
    param([string]$JsonContent)

    try {
        $obj = $JsonContent | ConvertFrom-Json -ErrorAction Stop
        if (-not $obj.version) {
            throw "Version field not found in JSON"
        }
        return $obj.version
    } catch {
        throw "Failed to parse version from JSON: $_"
    }
}

<#
.SYNOPSIS
    Convert version string into components (major, minor, patch, prerelease, metadata)

.PARAMETER Version
    Version string (e.g., "1.2.3", "1.2.3-alpha.1", "1.2.3+build.123")

.OUTPUTS
    PSCustomObject with Major, Minor, Patch, PreRelease, Metadata properties
#>
function ConvertVersionToSemanticParts {
    param([string]$Version)

    $versionPattern = '^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.-]+))?(?:\+([a-zA-Z0-9.-]+))?$'

    if ($Version -notmatch $versionPattern) {
        throw "Invalid semantic version format: $Version"
    }

    $matches = [regex]::Match($Version, $versionPattern)

    return @{
        Major      = [int]$matches.Groups[1].Value
        Minor      = [int]$matches.Groups[2].Value
        Patch      = [int]$matches.Groups[3].Value
        PreRelease = if ($matches.Groups[4].Success) { $matches.Groups[4].Value } else { $null }
        Metadata   = if ($matches.Groups[5].Success) { $matches.Groups[5].Value } else { $null }
    }
}

<#
.SYNOPSIS
    Parse conventional commit message to extract type, scope, subject, body

.PARAMETER Message
    Full commit message

.OUTPUTS
    PSCustomObject with Type, Scope, Subject, Body properties
#>
function ParseCommitMessage {
    param([string]$Message)

    $lines = @($Message -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })

    if ($lines.Count -eq 0) {
        throw "Invalid commit message format: empty message"
    }

    $headerLine = $lines[0]

    # Pattern: type(scope): subject or type: subject
    $headerPattern = '^([a-z]+)(?:\(([^)]+)\))?:\s*(.+)$'

    if ($headerLine -notmatch $headerPattern) {
        throw "Invalid commit message format: $headerLine. Expected 'type: subject' or 'type(scope): subject'"
    }

    $matches = [regex]::Match($headerLine, $headerPattern)
    $type = $matches.Groups[1].Value
    $scope = if ($matches.Groups[2].Success) { $matches.Groups[2].Value } else { $null }
    $subject = $matches.Groups[3].Value

    # Combine remaining lines as body (after header)
    $body = if ($lines.Count -gt 1) {
        ($lines | Select-Object -Skip 1) -join "`n"
    } else {
        $null
    }

    return @{
        Type    = $type
        Scope   = $scope
        Subject = $subject
        Body    = $body
    }
}

<#
.SYNOPSIS
    Determine next version based on conventional commits

.PARAMETER CurrentVersion
    Current semantic version (e.g., "1.0.0")

.PARAMETER Commits
    Array of commit objects with Type and Body properties

.OUTPUTS
    String: next semantic version
#>
function DetermineNextVersion {
    param(
        [string]$CurrentVersion,
        [object[]]$Commits
    )

    if (-not $Commits -or $Commits.Count -eq 0) {
        return $CurrentVersion
    }

    $parts = ConvertVersionToSemanticParts -Version $CurrentVersion
    $bumpType = "none"

    foreach ($commit in $Commits) {
        $hasBreaking = $commit.Body -and ($commit.Body -match "BREAKING CHANGE")

        if ($hasBreaking) {
            $bumpType = "major"
            break
        } elseif ($commit.Type -eq "feat" -and $bumpType -ne "major") {
            $bumpType = "minor"
        } elseif ($commit.Type -eq "fix" -and $bumpType -eq "none") {
            $bumpType = "patch"
        }
    }

    switch ($bumpType) {
        "major" {
            $parts.Major++
            $parts.Minor = 0
            $parts.Patch = 0
        }
        "minor" {
            $parts.Minor++
            $parts.Patch = 0
        }
        "patch" {
            $parts.Patch++
        }
    }

    return "$($parts.Major).$($parts.Minor).$($parts.Patch)"
}

<#
.SYNOPSIS
    Generate changelog entry from commits

.PARAMETER Commits
    Array of commit objects with Type, Scope, Subject properties

.PARAMETER Version
    Version number for the changelog entry

.OUTPUTS
    String: formatted changelog entry
#>
function GenerateChangelog {
    param(
        [object[]]$Commits,
        [string]$Version
    )

    $changelog = @("## $Version")
    $changelog += ""

    $features = @()
    $fixes = @()
    $other = @()

    foreach ($commit in $Commits) {
        $scopePart = if ($commit.Scope) { "**$($commit.Scope):** " } else { "" }
        $entry = "$scopePart$($commit.Subject)"

        switch ($commit.Type) {
            "feat" { $features += $entry }
            "fix" { $fixes += $entry }
            default { $other += $entry }
        }
    }

    if ($features.Count -gt 0) {
        $changelog += "### Features"
        $changelog += ""
        foreach ($feature in $features) {
            $changelog += "- $feature"
        }
        $changelog += ""
    }

    if ($fixes.Count -gt 0) {
        $changelog += "### Bug Fixes"
        $changelog += ""
        foreach ($fix in $fixes) {
            $changelog += "- $fix"
        }
        $changelog += ""
    }

    return $changelog -join "`n"
}

<#
.SYNOPSIS
    Update version field in JSON content

.PARAMETER JsonContent
    JSON string to update

.PARAMETER NewVersion
    New version value

.OUTPUTS
    String: updated JSON content
#>
function UpdateVersionFile {
    param(
        [string]$JsonContent,
        [string]$NewVersion
    )

    $obj = $JsonContent | ConvertFrom-Json
    $obj.version = $NewVersion
    return $obj | ConvertTo-Json -Depth 10
}

