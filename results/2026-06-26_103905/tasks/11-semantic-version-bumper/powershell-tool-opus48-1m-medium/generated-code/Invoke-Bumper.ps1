#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI orchestrator for the Semantic Version Bumper.

.DESCRIPTION
    Reads a current version (plain file or package.json) and a list of conventional
    commit messages (one per record in a commit log file), determines the next
    semantic version, updates the version file, prepends a changelog entry, and
    prints the new version.

    Output contract (stable, machine-parseable):
        NEW_VERSION=<x.y.z>
        PREVIOUS_VERSION=<x.y.z>
        BUMP_TYPE=<major|minor|patch|none>
    When running under GitHub Actions these are also written to $GITHUB_OUTPUT.

    Commit log format: messages are separated by a line containing only '---' so
    that multi-line commit bodies (e.g. BREAKING CHANGE footers) survive intact.
    A log without any '---' separators is treated as one message per line.

.EXAMPLE
    ./Invoke-Bumper.ps1 -VersionPath version.txt -CommitLogPath commits.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $VersionPath,
    [Parameter(Mandatory)][string] $CommitLogPath,
    [string] $ChangelogPath = 'CHANGELOG.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module that holds the logic (kept separate so it can be unit tested).
Import-Module (Join-Path $PSScriptRoot 'src' 'SemanticVersionBumper.psm1') -Force

function Read-CommitLog {
    <#
    .SYNOPSIS
        Reads commit messages from a log file into an array of message strings.
    #>
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Commit log file not found: '$Path'."
    }
    $raw = Get-Content -LiteralPath $Path -Raw

    if ($raw -match '(?m)^\s*---\s*$') {
        # Records separated by a '---' line: supports multi-line commit bodies.
        return ($raw -split '(?m)^\s*---\s*$') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    }
    # Otherwise one commit subject per line.
    return ($raw -split "`r?`n") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
}

try {
    $previous = Get-CurrentVersion -Path $VersionPath
    $commits  = @(Read-CommitLog -Path $CommitLogPath)

    if ($commits.Count -eq 0) {
        Write-Warning 'No commits found in commit log; version will be unchanged.'
    }

    $bump    = Get-BumpType -Commits $commits
    $newVer  = Step-Version -Version $previous -BumpType $bump

    if ($bump -ne 'none') {
        # Persist the new version.
        Set-CurrentVersion -Path $VersionPath -Version $newVer

        # Prepend the changelog entry, keeping prior history.
        $entry = New-ChangelogEntry -Version $newVer -Commits $commits
        $existing = if (Test-Path -LiteralPath $ChangelogPath) {
            Get-Content -LiteralPath $ChangelogPath -Raw
        } else {
            "# Changelog`n`n"
        }
        # Insert the new entry after the top-level title if one exists.
        if ($existing -match '^(# .*\r?\n\r?\n)') {
            $title = $Matches[1]
            $rest  = $existing.Substring($title.Length)
            Set-Content -LiteralPath $ChangelogPath -Value ($title + $entry + "`n" + $rest)
        } else {
            Set-Content -LiteralPath $ChangelogPath -Value ($entry + "`n" + $existing)
        }
        Write-Host "Updated $VersionPath and $ChangelogPath."
    }
    else {
        Write-Host 'No version-affecting commits; nothing to bump.'
    }

    # Emit the stable, parseable output contract.
    Write-Output "PREVIOUS_VERSION=$previous"
    Write-Output "BUMP_TYPE=$bump"
    Write-Output "NEW_VERSION=$newVer"

    # In CI, also surface as a step output.
    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "previous_version=$previous"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "bump_type=$bump"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "new_version=$newVer"
    }

    exit 0
}
catch {
    # Emit to the error stream non-terminatingly (the script-wide Stop preference
    # would otherwise make Write-Error terminating and skip the exit code), so the
    # message is both visible and capturable, then signal failure.
    Write-Error "Version bump failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
