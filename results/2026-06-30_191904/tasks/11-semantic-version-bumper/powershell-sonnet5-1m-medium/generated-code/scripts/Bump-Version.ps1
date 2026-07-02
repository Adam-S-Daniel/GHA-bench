<#
    .SYNOPSIS
    CLI entry point for the semantic version bumper. Reads the current
    version, classifies the commit log, bumps the version file, writes a
    changelog entry, and prints the resulting version so CI can capture it.
#>
param(
    [string]$VersionFilePath = 'version.json',
    [string]$CommitLogPath = 'commits.txt',
    [string]$ChangelogPath = 'CHANGELOG.md',
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'VersionBumper.psm1'
Import-Module $modulePath -Force

$result = Invoke-VersionBump -VersionFilePath $VersionFilePath `
    -CommitLogPath $CommitLogPath `
    -ChangelogPath $ChangelogPath `
    -Date $Date

Write-Host "Bump type: $($result.BumpType)"
Write-Host "Old version: $($result.OldVersion)"
Write-Host "New version: $($result.NewVersion)"

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "old_version=$($result.OldVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
}
