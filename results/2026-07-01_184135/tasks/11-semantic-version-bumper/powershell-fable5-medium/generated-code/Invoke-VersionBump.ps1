<#
.SYNOPSIS
    CLI entry point for the semantic version bumper.
.DESCRIPTION
    Reads the current version from a version file (plain text or
    package.json), determines the next version from a commit log file
    (one conventional commit message per line), updates the version file,
    prepends a changelog entry, and prints the new version.

    In GitHub Actions it also writes `new_version` / `bump_type` to
    $GITHUB_OUTPUT so downstream steps can consume them.
.EXAMPLE
    ./Invoke-VersionBump.ps1 -VersionFile version.txt -CommitLog commits.txt
#>
[CmdletBinding()]
param(
    [string]$VersionFile = 'version.txt',
    [string]$CommitLog = 'commits.txt',
    [string]$ChangelogPath = 'CHANGELOG.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src' 'VersionBumper.psm1') -Force

try {
    $result = Invoke-VersionBump -VersionFile $VersionFile `
        -CommitLog $CommitLog -ChangelogPath $ChangelogPath
}
catch {
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}

# Human/CI friendly output. The harness asserts on these exact lines.
Write-Host "OLD_VERSION=$($result.OldVersion)"
Write-Host "BUMP_TYPE=$($result.BumpType)"
Write-Host "NEW_VERSION=$($result.NewVersion)"

# Expose outputs to later workflow steps when running in GitHub Actions.
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
}
