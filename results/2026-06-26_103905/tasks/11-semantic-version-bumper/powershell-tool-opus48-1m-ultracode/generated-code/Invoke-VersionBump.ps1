#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    CLI entry point for the Semantic Version Bumper.

.DESCRIPTION
    Thin wrapper around the SemanticVersionBumper module. It is the script the
    GitHub Actions workflow calls. It:
      * resolves its inputs from parameters, falling back to environment
        variables (so the workflow can configure it with `env:` blocks),
      * runs the end-to-end bump (read version + commits -> next version ->
        update version file -> prepend changelog entry),
      * prints clearly-delimited marker lines (NEW_VERSION=..., etc.) for easy,
        exact-value assertions in CI logs,
      * exposes the results as GitHub Actions step outputs ($GITHUB_OUTPUT) and a
        job summary ($GITHUB_STEP_SUMMARY) when those are available,
      * exits non-zero with a meaningful message on any error.

.PARAMETER VersionFile
    Path to the version file or package.json. Falls back to $env:VERSION_FILE,
    then "VERSION".

.PARAMETER CommitLog
    Path to the commit-log file (one commit subject per line). Falls back to
    $env:COMMIT_LOG, then "commits.txt".

.PARAMETER ChangelogFile
    Path to the changelog file. Falls back to $env:CHANGELOG_FILE, then
    "CHANGELOG.md".

.PARAMETER Date
    Release date for the changelog entry (yyyy-MM-dd). Falls back to
    $env:RELEASE_DATE, then today (UTC). Parameterised so CI output is
    deterministic and testable.

.EXAMPLE
    ./Invoke-VersionBump.ps1 -VersionFile VERSION -CommitLog commits.txt
#>
[CmdletBinding()]
param(
    [string] $VersionFile,
    [string] $CommitLog,
    [string] $ChangelogFile,
    [string] $Date
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Helper: first non-empty value among the candidates (param > env > default).
function Resolve-Setting {
    param([string[]] $Candidates)
    foreach ($c in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c)) { return $c }
    }
    return $null
}

try {
    # Import the module relative to this script so it works from any CWD and
    # under `shell: pwsh` (where $PSScriptRoot is correctly populated).
    $modulePath = Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1'
    Import-Module $modulePath -Force

    # Resolve inputs: explicit parameter wins, then environment, then default.
    $resolvedVersionFile = Resolve-Setting @($VersionFile, $env:VERSION_FILE, 'VERSION')
    $resolvedCommitLog   = Resolve-Setting @($CommitLog, $env:COMMIT_LOG, 'commits.txt')
    $resolvedChangelog   = Resolve-Setting @($ChangelogFile, $env:CHANGELOG_FILE, 'CHANGELOG.md')
    $resolvedDate        = Resolve-Setting @($Date, $env:RELEASE_DATE, ([System.DateTime]::UtcNow.ToString('yyyy-MM-dd')))

    Write-Host "Semantic Version Bumper"
    Write-Host "  version file : $resolvedVersionFile"
    Write-Host "  commit log   : $resolvedCommitLog"
    Write-Host "  changelog    : $resolvedChangelog"
    Write-Host "  date         : $resolvedDate"

    $result = Invoke-VersionBump `
        -VersionFile $resolvedVersionFile `
        -CommitLog $resolvedCommitLog `
        -ChangelogFile $resolvedChangelog `
        -Date $resolvedDate

    # Clearly-delimited marker lines for exact-value assertions in CI logs.
    Write-Host "PREVIOUS_VERSION=$($result.PreviousVersion)"
    Write-Host "BUMP_TYPE=$($result.BumpType)"
    Write-Host "NEW_VERSION=$($result.NewVersion)"

    Write-Host ""
    Write-Host "----- CHANGELOG ENTRY -----"
    Write-Host $result.ChangelogEntry
    Write-Host "---------------------------"

    # Expose results as GitHub Actions step outputs when running in CI.
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "new_version=$($result.NewVersion)"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "previous_version=$($result.PreviousVersion)"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "bump_type=$($result.BumpType)"
    }

    # Write a friendly job summary when running in CI.
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
        $summary = @(
            "## Semantic Version Bump",
            "",
            "| Field | Value |",
            "| ----- | ----- |",
            "| Previous version | $($result.PreviousVersion) |",
            "| New version | $($result.NewVersion) |",
            "| Bump type | $($result.BumpType) |",
            "| Commits considered | $($result.CommitCount) |",
            "",
            "### Changelog entry",
            "",
            $result.ChangelogEntry
        ) -join "`n"
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary
    }

    exit 0
}
catch {
    # Surface a meaningful, single-line error and fail the step.
    Write-Error "Semantic version bump failed: $($_.Exception.Message)"
    exit 1
}
