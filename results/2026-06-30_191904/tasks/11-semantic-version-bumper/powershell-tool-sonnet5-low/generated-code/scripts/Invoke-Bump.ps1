# Invoke-Bump.ps1
# CLI entry point used by the GitHub Actions workflow. Reads commit messages
# from a log file (one per line, conventional-commit style), bumps the
# version file/package.json accordingly, updates CHANGELOG.md, and prints the
# new version to stdout so the workflow step can capture it.
param(
    [Parameter(Mandatory)]
    [string]$VersionFilePath,

    [Parameter(Mandatory)]
    [string]$CommitLogPath,

    [string]$ChangelogPath = (Join-Path (Split-Path -Parent $VersionFilePath) 'CHANGELOG.md')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'VersionBumper.psm1') -Force

if (-not (Test-Path -Path $CommitLogPath)) {
    throw "Commit log file not found: $CommitLogPath"
}

$commitMessages = @(Get-Content -Path $CommitLogPath)

$result = Invoke-VersionBump -VersionFilePath $VersionFilePath -ChangelogPath $ChangelogPath -CommitMessages $commitMessages

Write-Host "Previous version: $($result.PreviousVersion)"
Write-Host "Bump type: $($result.BumpType)"
Write-Host "New version: $($result.NewVersion)"

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
}
