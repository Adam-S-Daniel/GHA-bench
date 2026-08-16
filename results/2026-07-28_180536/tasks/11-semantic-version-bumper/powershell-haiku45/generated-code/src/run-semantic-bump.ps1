#!/usr/bin/env pwsh
# Main entry point script for GitHub Actions workflow
# Runs semantic version bumping with actual git commit history

param(
    [Parameter(Mandatory=$false)]
    [string]$VersionFilePath = "package.json",

    [Parameter(Mandatory=$false)]
    [string]$ChangelogFilePath = "CHANGELOG.md",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Import functions from main script
. $PSScriptRoot/semver-bumper.ps1

try {
    # Get all commits since last tag or from root
    $lastTag = git describe --tags --abbrev=0 2>$null
    if ($LASTEXITCODE -ne 0) {
        $commitRange = "HEAD"
    } else {
        $commitRange = "$lastTag..HEAD"
    }

    # Get commit messages
    $rawCommits = git log $commitRange --pretty=format:"%s"
    $commitMessages = if ($rawCommits) {
        @($rawCommits -split "`n") | Where-Object { $_ }
    } else {
        @()
    }

    if ($commitMessages.Count -eq 0) {
        Write-Warning "No commits found. Exiting without version bump."
        exit 0
    }

    # Invoke the version bump function
    $result = Invoke-SemanticVersionBump -VersionFilePath $VersionFilePath `
        -CommitMessages $commitMessages `
        -ChangelogFilePath $ChangelogFilePath `
        -DryRun:$DryRun

    # Output results for GitHub Actions
    Write-Host "::group::Version Bump Summary"
    Write-Host "Current Version: $($result.CurrentVersion)"
    Write-Host "Next Version: $($result.NextVersion)"
    Write-Host "Commits Processed: $($commitMessages.Count)"
    Write-Host "::endgroup::"

    # Set output variables for workflow
    Write-Host "current_version=$($result.CurrentVersion)" >> $env:GITHUB_OUTPUT
    Write-Host "next_version=$($result.NextVersion)" >> $env:GITHUB_OUTPUT
    Write-Host "changelog=$([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($result.Changelog)))" >> $env:GITHUB_OUTPUT

    exit 0
} catch {
    Write-Error "Semantic version bump failed: $_"
    exit 1
}
