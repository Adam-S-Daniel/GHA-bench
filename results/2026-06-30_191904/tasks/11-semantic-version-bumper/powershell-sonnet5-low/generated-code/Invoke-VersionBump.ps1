<#
.SYNOPSIS
    CLI entry point for the semantic version bumper. Used by the GitHub Actions
    workflow to bump a version file based on conventional commit messages.
.PARAMETER VersionFilePath
    Path to the version file (package.json or a plain VERSION text file).
.PARAMETER CommitLogPath
    Path to a text file containing one commit message per line.
.PARAMETER ChangelogPath
    Path to the CHANGELOG.md file to prepend the new entry to.
#>
param(
    [Parameter(Mandatory)]
    [string]$VersionFilePath,

    [Parameter(Mandatory)]
    [string]$CommitLogPath,

    [Parameter()]
    [string]$ChangelogPath = 'CHANGELOG.md',

    [Parameter()]
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1') -Force

$result = Invoke-VersionBump -VersionFilePath $VersionFilePath -CommitLogPath $CommitLogPath `
    -ChangelogPath $ChangelogPath -Date $Date

Write-Output "PreviousVersion=$($result.PreviousVersion)"
Write-Output "NewVersion=$($result.NewVersion)"
Write-Output "BumpType=$($result.BumpType)"

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "previous_version=$($result.PreviousVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
}
