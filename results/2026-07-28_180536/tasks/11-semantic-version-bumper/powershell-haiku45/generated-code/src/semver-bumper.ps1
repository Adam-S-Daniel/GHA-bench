# Semantic Version Bumper - TDD Implementation
# Parses version files, analyzes conventional commits, and generates next version

# Parse current version from package.json or version file
function Get-CurrentVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    $content = Get-Content -Path $FilePath -Raw
    $json = $content | ConvertFrom-Json
    return $json.version
}

# Determine next version based on conventional commit types
function Get-NextVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentVersion,

        [Parameter(Mandatory=$true)]
        [string[]]$CommitMessages
    )

    # Parse current version
    $parts = $CurrentVersion -split '\.'
    [int]$major = $parts[0]
    [int]$minor = $parts[1]
    [int]$patch = $parts[2]

    # Determine bump type: major, minor, patch (default)
    $bumpType = "patch"

    foreach ($message in $CommitMessages) {
        if ($message -match 'BREAKING CHANGE') {
            $bumpType = "major"
            break  # Breaking change has highest priority
        }
    }

    if ($bumpType -eq "patch") {
        foreach ($message in $CommitMessages) {
            if ($message -match '^feat:') {
                $bumpType = "minor"
                break
            }
        }
    }

    if ($bumpType -eq "patch") {
        foreach ($message in $CommitMessages) {
            if ($message -match '^fix:') {
                $bumpType = "patch"
            }
        }
    }

    # Apply bump
    switch ($bumpType) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "minor" {
            $minor++
            $patch = 0
        }
        "patch" {
            $patch++
        }
    }

    return "$major.$minor.$patch"
}

# Update version in package.json
function Update-VersionFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$NewVersion
    )

    $content = Get-Content -Path $FilePath -Raw
    $json = $content | ConvertFrom-Json

    # Update the version
    $json.version = $NewVersion

    # Convert back to JSON and write
    $json | ConvertTo-Json | Set-Content -Path $FilePath
}

# Generate changelog entry from commit messages
function Generate-ChangelogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version,

        [Parameter(Mandatory=$true)]
        [string[]]$CommitMessages
    )

    $changelog = "## [$Version] - $(Get-Date -Format 'yyyy-MM-dd')`n`n"

    # Separate commits by type
    $features = @()
    $fixes = @()
    $breaking = @()

    foreach ($message in $CommitMessages) {
        if ($message -match 'BREAKING CHANGE') {
            $breaking += $message
        } elseif ($message -match '^feat:(.+)$') {
            $features += $message -replace '^feat:\s*', '- '
        } elseif ($message -match '^fix:(.+)$') {
            $fixes += $message -replace '^fix:\s*', '- '
        }
    }

    if ($breaking.Count -gt 0) {
        $changelog += "### ⚠️ BREAKING CHANGES`n"
        foreach ($msg in $breaking) {
            $changelog += "- $msg`n"
        }
        $changelog += "`n"
    }

    if ($features.Count -gt 0) {
        $changelog += "### Features`n"
        foreach ($msg in $features) {
            $changelog += "$msg`n"
        }
        $changelog += "`n"
    }

    if ($fixes.Count -gt 0) {
        $changelog += "### Bug Fixes`n"
        foreach ($msg in $fixes) {
            $changelog += "$msg`n"
        }
    }

    return $changelog
}

# Main entry point for CI/CD pipeline
function Invoke-SemanticVersionBump {
    param(
        [Parameter(Mandatory=$false)]
        [string]$VersionFilePath = "package.json",

        [Parameter(Mandatory=$false)]
        [string[]]$CommitMessages = @(),

        [Parameter(Mandatory=$false)]
        [string]$ChangelogFilePath = "CHANGELOG.md",

        [Parameter(Mandatory=$false)]
        [switch]$DryRun
    )

    try {
        # Get current version
        if (-not (Test-Path $VersionFilePath)) {
            throw "Version file not found: $VersionFilePath"
        }

        $currentVersion = Get-CurrentVersion -FilePath $VersionFilePath
        Write-Host "Current version: $currentVersion"

        # Get next version
        if ($CommitMessages.Count -eq 0) {
            throw "No commit messages provided"
        }

        $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -CommitMessages $CommitMessages
        Write-Host "Next version: $nextVersion"

        # Generate changelog
        $changelogEntry = Generate-ChangelogEntry -Version $nextVersion -CommitMessages $CommitMessages

        if (-not $DryRun) {
            # Update version file
            Update-VersionFile -FilePath $VersionFilePath -NewVersion $nextVersion

            # Append to changelog
            if (Test-Path $ChangelogFilePath) {
                $existingChangelog = Get-Content -Path $ChangelogFilePath -Raw
                $changelogEntry + "`n`n" + $existingChangelog | Set-Content -Path $ChangelogFilePath
            } else {
                $changelogEntry | Set-Content -Path $ChangelogFilePath
            }

            Write-Host "Version updated to $nextVersion"
        } else {
            Write-Host "[DRY RUN] Would update to version $nextVersion"
        }

        return @{
            CurrentVersion = $currentVersion
            NextVersion    = $nextVersion
            Changelog      = $changelogEntry
        }
    } catch {
        Write-Error "Error bumping version: $_"
        exit 1
    }
}

# Functions are automatically available when dot-sourced
# No explicit export needed for script files
