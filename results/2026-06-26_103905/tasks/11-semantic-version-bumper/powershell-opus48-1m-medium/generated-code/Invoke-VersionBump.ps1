#!/usr/bin/env pwsh
# Invoke-VersionBump.ps1
# Thin CLI wrapper around SemanticVersionBumper.psm1, designed to be called from
# the GitHub Actions workflow. It reads the version file and commit log, computes
# and applies the bump, updates the changelog, and emits machine-parseable output.
#
# Output contract (one key=value per line on stdout, plus GITHUB_OUTPUT when set):
#   OLD_VERSION=<x>
#   NEW_VERSION=<y>
#   BUMP_TYPE=<major|minor|patch|none>

[CmdletBinding()]
param(
    [string]$VersionFilePath = $(if ($env:VERSION_FILE) { $env:VERSION_FILE } else { 'version.txt' }),
    [string]$CommitLogPath   = $(if ($env:COMMIT_LOG)   { $env:COMMIT_LOG }   else { 'commits.txt' }),
    [string]$ChangelogPath   = $(if ($env:CHANGELOG)    { $env:CHANGELOG }    else { 'CHANGELOG.md' }),
    # Optional fixed date for deterministic output (used by the test harness).
    [string]$Date            = $env:BUMP_DATE
)

$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1'
    Import-Module $modulePath -Force

    $result = Invoke-VersionBump -VersionFilePath $VersionFilePath `
        -CommitLogPath $CommitLogPath -ChangelogPath $ChangelogPath -Date $Date

    # Human-friendly summary to stderr-ish (still stdout, but clearly labelled).
    Write-Host "Semantic Version Bumper"
    Write-Host "  Old version: $($result.OldVersion)"
    Write-Host "  Bump type:   $($result.BumpType)"
    Write-Host "  New version: $($result.NewVersion)"

    # Machine-parseable lines the test harness asserts on.
    Write-Output "OLD_VERSION=$($result.OldVersion)"
    Write-Output "NEW_VERSION=$($result.NewVersion)"
    Write-Output "BUMP_TYPE=$($result.BumpType)"

    # Expose results as step outputs when running inside GitHub Actions / act.
    if ($env:GITHUB_OUTPUT) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "old_version=$($result.OldVersion)"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
    }

    exit 0
}
catch {
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}
