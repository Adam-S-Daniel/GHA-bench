<#
    .SYNOPSIS
    CLI entry point for the semantic version bumper.

    .DESCRIPTION
    Reads the current version from a version file, inspects the project's
    real git history for conventional commits since the last tag, computes
    the next semantic version (feat -> minor, fix -> patch, breaking -> major),
    writes the bumped version back to the version file, prepends a changelog
    entry, and reports the result (stdout + $GITHUB_OUTPUT when running in
    GitHub Actions).

    This script is intentionally a thin orchestration layer over the pure,
    independently unit-tested functions in VersionBumper.psm1 -- it is
    exercised end-to-end via the GitHub Actions workflow (run locally
    through `act`), not via direct unit tests.

    .PARAMETER VersionFile
    Path to the version file (plain text VERSION file, or a *.json file
    such as package.json with a top-level "version" field).

    .PARAMETER ChangelogFile
    Path to the changelog file to prepend the new entry to.

    .PARAMETER CommitRange
    Optional explicit git revision range (e.g. "v1.0.0..HEAD"). Defaults to
    every commit since the most recent tag, or the whole history if there
    is no tag yet.
#>
[CmdletBinding()]
param(
    [string] $VersionFile = 'VERSION',
    [string] $ChangelogFile = 'CHANGELOG.md',
    [string] $CommitRange
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'VersionBumper.psm1') -Force

function Write-GitHubOutput {
    param([hashtable] $Values)

    if (-not $env:GITHUB_OUTPUT) { return }
    foreach ($key in $Values.Keys) {
        "$key=$($Values[$key])" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
}

try {
    $currentVersion = Get-CurrentVersion -Path $VersionFile
    Write-Host "Current version: $currentVersion"

    $commitMessages = Get-CommitMessagesFromGit -Range $CommitRange
    Write-Host "Inspecting $($commitMessages.Count) commit(s) for conventional-commit markers."

    $bumpType = Get-BumpType -CommitMessages $commitMessages

    if (-not $bumpType) {
        Write-Host 'No feat/fix/breaking commits found; version left unchanged.'
        Write-GitHubOutput @{
            version          = $currentVersion
            previous_version = $currentVersion
            bumped           = 'false'
        }
        exit 0
    }

    $newVersion = Get-NextVersion -CurrentVersion $currentVersion -BumpType $bumpType
    Update-VersionFile -Path $VersionFile -NewVersion $newVersion

    $changelogEntry = New-ChangelogEntry -Version $newVersion -CommitMessages $commitMessages
    Add-ChangelogEntry -Path $ChangelogFile -Entry $changelogEntry

    Write-Host "Bump type: $bumpType"
    Write-Host "Previous version: $currentVersion"
    Write-Host "New version: $newVersion"

    Write-GitHubOutput @{
        version          = $newVersion
        previous_version = $currentVersion
        bump_type        = $bumpType
        bumped           = 'true'
    }
}
catch {
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}
