<#
.SYNOPSIS
    CLI entry point for the semantic version bumper.

.DESCRIPTION
    Thin wrapper around the SemanticVersionBumper module so CI pipelines
    (see .github/workflows/semantic-version-bumper.yml) can run the bump
    as a single script call. Prints the new version to stdout; on any
    failure prints a meaningful error and exits with code 1.

.EXAMPLE
    ./src/Invoke-VersionBump.ps1 -VersionFile VERSION -CommitLogFile commit-log.txt -ChangelogFile CHANGELOG.md
#>
[CmdletBinding()]
param(
    # VERSION file or package.json holding the current semantic version.
    [Parameter(Mandatory)]
    [string]$VersionFile,

    # Commit log file: commit messages separated by '---' lines.
    [Parameter(Mandatory)]
    [string]$CommitLogFile,

    # Changelog file to prepend the generated release notes to.
    [Parameter(Mandatory)]
    [string]$ChangelogFile,

    # Optional fixed release date (yyyy-MM-dd); defaults to today.
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1') -Force

    $newVersion = Invoke-VersionBump `
        -VersionFile $VersionFile `
        -CommitLogFile $CommitLogFile `
        -ChangelogFile $ChangelogFile `
        -Date $Date

    # The new version is the script's contract with the pipeline.
    Write-Output $newVersion
    exit 0
}
catch {
    # -ErrorAction Continue so the message is emitted even when the caller
    # runs with $ErrorActionPreference = 'Stop' (as GitHub Actions does),
    # guaranteeing we reach the explicit exit code below.
    Write-Error -Message "Version bump failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
