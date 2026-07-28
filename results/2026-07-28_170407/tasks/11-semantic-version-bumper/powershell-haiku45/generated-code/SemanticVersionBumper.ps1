# Parse a semantic version string, extracting major, minor, patch components
function Parse-Version {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionString
    )

    $clean = $VersionString -replace "^v", ""

    if ($clean -notmatch "^(\d+)\.(\d+)\.(\d+)$") {
        throw "Invalid version format: '$VersionString'"
    }

    $matches = [System.Text.RegularExpressions.Regex]::Match($clean, "^(\d+)\.(\d+)\.(\d+)$")

    return [PSCustomObject]@{
        Major   = [int]$matches.Groups[1].Value
        Minor   = [int]$matches.Groups[2].Value
        Patch   = [int]$matches.Groups[3].Value
    }
}

# Determine bump type (major/minor/patch) from a commit message using conventional commits
function Get-CommitType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommitMessage
    )

    if ($CommitMessage -match "BREAKING\s*CHANGE") {
        return "major"
    }

    if ($CommitMessage -match "^feat!:|^fix!:|^docs!:|^style!:|^refactor!:|^perf!:|^test!:") {
        return "major"
    }

    if ($CommitMessage -match "^feat:") {
        return "minor"
    }

    return "patch"
}

# Increment version based on bump type
function Bump-Version {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Version,

        [Parameter(Mandatory = $true)]
        [ValidateSet("major", "minor", "patch")]
        [string]$BumpType
    )

    $new = $Version | Select-Object -Property Major, Minor, Patch

    switch ($BumpType) {
        "major" {
            $new.Major += 1
            $new.Minor = 0
            $new.Patch = 0
        }
        "minor" {
            $new.Minor += 1
            $new.Patch = 0
        }
        "patch" {
            $new.Patch += 1
        }
    }

    return $new
}

# Generate a changelog from commits
function Build-Changelog {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Commits,

        [Parameter(Mandatory = $true)]
        [string]$NewVersion
    )

    $grouped = $Commits | Group-Object -Property Type

    $changelog = @"
## [$NewVersion] - $(Get-Date -Format "yyyy-MM-dd")

"@

    $typeOrder = @("feat", "fix", "perf", "refactor", "docs", "style", "test", "chore")

    foreach ($type in $typeOrder) {
        $group = $grouped | Where-Object { $_.Name -eq $type }
        if ($group) {
            $heading = switch ($type) {
                "feat" { "Features" }
                "fix" { "Fixes" }
                "perf" { "Performance" }
                "refactor" { "Refactoring" }
                "docs" { "Documentation" }
                "style" { "Styling" }
                "test" { "Tests" }
                "chore" { "Chores" }
                default { $type }
            }

            $changelog += "### $heading`n`n"

            foreach ($commit in $group.Group) {
                $changelog += "- $($commit.Message) ($($commit.Hash))`n"
            }

            $changelog += "`n"
        }
    }

    return $changelog
}

# Create realistic mock commit logs for testing
function New-MockCommitLog {
    param(
        [int]$Count = 5,
        [switch]$IncludeBreaking
    )

    $commitMessages = @(
        @{ Type = "feat"; Message = "add user authentication" }
        @{ Type = "feat"; Message = "implement API rate limiting" }
        @{ Type = "fix"; Message = "resolve null reference exception" }
        @{ Type = "fix"; Message = "correct database query timeout" }
        @{ Type = "refactor"; Message = "simplify service layer" }
        @{ Type = "docs"; Message = "update README with examples" }
        @{ Type = "test"; Message = "add integration tests" }
        @{ Type = "perf"; Message = "optimize query performance" }
    )

    $breakingMessages = @(
        @{ Type = "feat"; Message = "redesign API endpoints`n`nBREAKING CHANGE: old endpoints removed" }
        @{ Type = "feat"; Message = "migrate to new auth system`n`nBREAKING CHANGE: legacy tokens no longer supported" }
    )

    $commits = @()
    for ($i = 0; $i -lt $Count; $i++) {
        if ($IncludeBreaking -and (Get-Random -Minimum 0 -Maximum 10) -lt 2) {
            $msg = $breakingMessages | Get-Random
        } else {
            $msg = $commitMessages | Get-Random
        }

        $hash = [guid]::NewGuid().ToString().Substring(0, 7)

        $commits += [PSCustomObject]@{
            Type    = $msg.Type
            Message = $msg.Message
            Hash    = $hash
        }
    }

    return $commits
}

# Process a version file and return the new version string
function Process-VersionFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$CommitLog
    )

    if (-not (Test-Path $Path)) {
        throw "Version file not found: $Path"
    }

    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $currentVersion = Parse-Version $content.version

    # Determine the highest bump needed
    $bumpType = "patch"
    foreach ($commit in $CommitLog) {
        $commitBump = Get-CommitType $commit.Message

        if ($commitBump -eq "major") {
            $bumpType = "major"
            break
        } elseif ($commitBump -eq "minor" -and $bumpType -ne "major") {
            $bumpType = "minor"
        }
    }

    $newVersion = Bump-Version $currentVersion $bumpType

    return "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
}
