<#
.SYNOPSIS
    CLI entry point for the semantic version bumper. Wraps the pure
    VersionBumper module functions with argument handling, console output,
    GitHub Actions output wiring, and error handling.

.DESCRIPTION
    Reads the current version from -VersionFilePath (a plain-text VERSION
    file or a package.json), classifies commits since the last release
    (from -CommitLogPath if given, otherwise real `git log`) using
    conventional-commit rules (feat -> minor, fix -> patch,
    breaking/! -> major), computes the next version, updates the version
    file in place, and prepends a changelog entry to -ChangelogFilePath.

    On success, prints "New version: X.Y.Z" and, when $env:GITHUB_OUTPUT is
    set (i.e. running inside a GitHub Actions step), appends
    "new_version=X.Y.Z" to it so downstream steps/jobs can consume the
    result via `${{ steps.<id>.outputs.new_version }}`.

    On failure, writes a clear error message to stderr and exits 1 so the
    calling CI job fails loudly instead of silently continuing.

.EXAMPLE
    ./scripts/Invoke-SemanticVersionBumper.ps1 -VersionFilePath ./VERSION -ChangelogFilePath ./CHANGELOG.md

.EXAMPLE
    ./scripts/Invoke-SemanticVersionBumper.ps1 -VersionFilePath ./package.json -CommitLogPath ./fixtures/commits.log -ChangelogFilePath ./CHANGELOG.md
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$VersionFilePath = './VERSION',

    [Parameter()]
    [string]$CommitLogPath,

    [Parameter()]
    [string]$ChangelogFilePath = './CHANGELOG.md',

    [Parameter()]
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd')
)

$ModulePath = Join-Path $PSScriptRoot '..' 'src' 'VersionBumper.psm1'
Import-Module $ModulePath -Force

try {
    $result = Invoke-VersionBump -VersionFilePath $VersionFilePath `
        -CommitLogPath $CommitLogPath `
        -ChangelogFilePath $ChangelogFilePath `
        -Date $Date

    Write-Host "Old version: $($result.OldVersion)"
    Write-Host "Bump type: $($result.BumpType)"
    Write-Host "New version: $($result.NewVersion)"

    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "old_version=$($result.OldVersion)"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
    }

    exit 0
} catch {
    # -ErrorAction Continue is explicit here (not just relying on the
    # default): GitHub Actions' `shell: pwsh` steps prepend
    # `$ErrorActionPreference = 'Stop'`, which would otherwise turn this
    # Write-Error into a terminating error that skips `exit 1` below and
    # instead bubbles out of the script entirely.
    Write-Error "semantic-version-bumper failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
