#Requires -Version 7.0
<#
.SYNOPSIS
    Semantic version bumper CLI - parse version, determine next version from commits, update files

.DESCRIPTION
    Reads a package.json file, analyzes conventional commit messages,
    bumps the semantic version accordingly, and generates a changelog.

    Version bump rules:
    - BREAKING CHANGE in commit body → major version bump
    - feat: commit type → minor version bump
    - fix: commit type → patch version bump

.PARAMETER PackageFile
    Path to package.json file (default: ./package.json)

.PARAMETER CommitLog
    Git commit log (newline-separated commit messages). If not provided, reads from git.

.PARAMETER OutputFile
    Path to write updated package.json (default: same as input file)

.PARAMETER ChangelogFile
    Path to write changelog (default: ./CHANGELOG.md)

.EXAMPLE
    ./bump-version.ps1 -PackageFile ./package.json -CommitLog @"
    feat: add user authentication
    fix: resolve button alignment
    "@

.EXAMPLE
    # Use with git log
    $commits = git log --pretty="%B" v1.0.0..HEAD
    ./bump-version.ps1 -CommitLog $commits
#>

param(
    [string]$PackageFile = "./package.json",
    [string]$CommitLog = $null,
    [string]$OutputFile = $null,
    [string]$ChangelogFile = "./CHANGELOG.md"
)

# Source the implementation
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir/SemanticVersionBumper.ps1"
. "$scriptDir/test-fixtures.ps1"

function Invoke-SemanticVersionBump {
    param(
        [string]$PackageFile,
        [string]$CommitLog,
        [string]$OutputFile,
        [string]$ChangelogFile
    )

    # Set output file to input file if not specified
    if (-not $OutputFile) {
        $OutputFile = $PackageFile
    }

    try {
        # Read current package.json
        if (-not (Test-Path $PackageFile)) {
            throw "Package file not found: $PackageFile"
        }

        $packageContent = Get-Content -Path $PackageFile -Raw
        $currentVersion = ParseVersion -JsonContent $packageContent

        Write-Host "Current version: $currentVersion"

        # Parse commits from log
        $commits = @()
        if ($CommitLog) {
            $commitMessages = $CommitLog -split "`n`n" | Where-Object { $_.Trim() }
            foreach ($message in $commitMessages) {
                try {
                    $parsed = ParseCommitMessage -Message $message
                    $commits += $parsed
                } catch {
                    Write-Warning "Skipped invalid commit message: $_"
                }
            }
        }

        Write-Host "Parsed $($commits.Count) commits"

        # Determine next version
        $nextVersion = DetermineNextVersion -CurrentVersion $currentVersion -Commits $commits

        Write-Host "Next version: $nextVersion"

        # Update package.json if version changed
        if ($nextVersion -ne $currentVersion) {
            $updatedPackage = UpdateVersionFile -JsonContent $packageContent -NewVersion $nextVersion
            Set-Content -Path $OutputFile -Value $updatedPackage
            Write-Host "Updated package.json: $OutputFile"
        } else {
            Write-Host "No version change needed"
        }

        # Generate changelog
        if ($commits.Count -gt 0) {
            $changelog = GenerateChangelog -Commits $commits -Version $nextVersion
            Add-Content -Path $ChangelogFile -Value $changelog -Encoding UTF8
            Write-Host "Generated changelog: $ChangelogFile"
        }

        # Output results for CI/CD
        Write-Output "version=$nextVersion"
        return $nextVersion

    } catch {
        Write-Error "Error during version bump: $_"
        exit 1
    }
}

# Main execution
$result = Invoke-SemanticVersionBump -PackageFile $PackageFile -CommitLog $CommitLog -OutputFile $OutputFile -ChangelogFile $ChangelogFile

if ($result) {
    exit 0
} else {
    exit 1
}
