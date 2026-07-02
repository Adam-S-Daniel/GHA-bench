<#
.SYNOPSIS
    CI-facing entry point: runs the semantic version bump against a
    VERSION file (or package.json) and a commit log, then prints the
    result in a form the GitHub Actions workflow can capture.
#>
[CmdletBinding()]
param(
    [string]$VersionFilePath = 'VERSION',
    [Parameter(Mandatory)]
    [string]$CommitLogPath,
    [string]$ChangelogPath = 'CHANGELOG.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'VersionBumper.psm1') -Force

$result = Invoke-SemanticVersionBump -VersionFilePath $VersionFilePath -CommitLogPath $CommitLogPath -ChangelogPath $ChangelogPath

Write-Output "PREVIOUS_VERSION=$($result.PreviousVersion)"
Write-Output "NEW_VERSION=$($result.NewVersion)"
Write-Output "BUMP_TYPE=$($result.BumpType)"

if ($env:GITHUB_OUTPUT) {
    "previous_version=$($result.PreviousVersion)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "new_version=$($result.NewVersion)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "bump_type=$($result.BumpType)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
