#!/usr/bin/env pwsh
#
# Invoke-VersionBump.ps1
#
# Thin CLI wrapper around the SemanticVersionBumper module, intended to be the
# entry point used by CI (the GitHub Actions workflow calls this directly).
#
# It reads a version file and a commit-log fixture, computes & applies the next
# semantic version, writes a changelog entry, prints a clear, parseable summary,
# and (when running under GitHub Actions) exports step outputs.
#
# Usage:
#   ./Invoke-VersionBump.ps1 -VersionFile VERSION -CommitLog commits.log
#

[CmdletBinding()]
param(
    # Path to the VERSION file or package.json holding the current version.
    [Parameter(Mandatory)]
    [string]$VersionFile,

    # Path to the commit log fixture ("<hash> <subject>" per line).
    [Parameter(Mandatory)]
    [string]$CommitLog,

    # Changelog file to create/update.
    [string]$ChangelogFile = 'CHANGELOG.md',

    # Release date stamped into the changelog (defaults to today).
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

# Fail fast and loudly on any error so CI surfaces problems clearly.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    # Import the module that lives alongside this script.
    $modulePath = Join-Path $PSScriptRoot 'src/SemanticVersionBumper.psm1'
    Import-Module $modulePath -Force

    $result = Invoke-VersionBump -VersionFile $VersionFile -CommitLog $CommitLog `
        -ChangelogFile $ChangelogFile -Date $Date

    # Human/CI readable summary. The act harness asserts on these exact lines.
    Write-Host "previous_version=$($result.PreviousVersion)"
    Write-Host "new_version=$($result.NewVersion)"
    Write-Host "bump_type=$($result.BumpType)"
    Write-Host "bumped=$($result.Bumped)"
    Write-Host "commit_count=$($result.CommitCount)"

    if ($result.Bumped) {
        Write-Host "----- CHANGELOG ENTRY -----"
        Write-Host $result.ChangelogEntry
        Write-Host "---------------------------"
    }
    else {
        Write-Host "No conventional commits warranted a version bump; nothing changed."
    }

    # Export GitHub Actions step outputs when available.
    if ($env:GITHUB_OUTPUT) {
        "previous_version=$($result.PreviousVersion)" | Add-Content -Path $env:GITHUB_OUTPUT
        "new_version=$($result.NewVersion)"           | Add-Content -Path $env:GITHUB_OUTPUT
        "bump_type=$($result.BumpType)"               | Add-Content -Path $env:GITHUB_OUTPUT
        "bumped=$($result.Bumped)"                    | Add-Content -Path $env:GITHUB_OUTPUT
    }

    exit 0
}
catch {
    # Meaningful, single-line error message to stderr plus a non-zero exit.
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}
