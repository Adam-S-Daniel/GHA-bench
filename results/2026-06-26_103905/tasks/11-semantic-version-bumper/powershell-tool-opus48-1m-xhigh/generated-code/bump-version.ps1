#!/usr/bin/env pwsh
#
# bump-version.ps1 — CLI entry point for the semantic version bumper.
#
# Thin wrapper around the SemanticVersionBumper library: it gathers inputs
# (parameters, falling back to environment variables so the GitHub Actions
# workflow can drive it), runs Invoke-VersionBump, and emits machine-parseable
# output plus, when running inside GitHub Actions/act, step outputs and a job
# summary.
#
# Output contract (stdout) — stable, one key per line, easy to grep/assert:
#     PREVIOUS_VERSION=<old>
#     BUMP_TYPE=<major|minor|patch|none>
#     NEW_VERSION=<new>
#     CHANGED=<true|false>
#
# Exit codes: 0 success, 1 on any handled error (with a clear message on stderr).

[CmdletBinding()]
param(
    # Path to the version file. When omitted, falls back to $env:VERSION_FILE,
    # then auto-detection (version.txt / VERSION / package.json) in -RepositoryPath.
    [string] $VersionFile = $env:VERSION_FILE,

    # Path to a commit-log fixture file (one commit subject per line). When
    # omitted, falls back to $env:COMMIT_LOG_FILE, then real git history.
    [string] $CommitLogFile = $env:COMMIT_LOG_FILE,

    # Changelog file to prepend the new entry to.
    [string] $ChangelogFile = $(if ($env:CHANGELOG_FILE) { $env:CHANGELOG_FILE } else { 'CHANGELOG.md' }),

    # Repository root used for auto-detection and git history.
    [string] $RepositoryPath = '.',

    # Release date (yyyy-MM-dd). Defaults to today; overridable for reproducibility.
    [string] $Date = $(if ($env:RELEASE_DATE) { $env:RELEASE_DATE } else { (Get-Date -Format 'yyyy-MM-dd') })
)

# Stop on any error so failures surface as a non-zero exit rather than partial work.
$ErrorActionPreference = 'Stop'

# Load the library that sits next to this script.
. (Join-Path $PSScriptRoot 'src/SemanticVersionBumper.ps1')

try {
    $params = @{
        ChangelogFile  = $ChangelogFile
        RepositoryPath = $RepositoryPath
        Date           = $Date
    }
    if ($VersionFile)   { $params.VersionFile   = $VersionFile }
    if ($CommitLogFile) { $params.CommitLogFile = $CommitLogFile }

    $result = Invoke-VersionBump @params

    # --- Human-readable banner ---
    if ($result.Changed) {
        Write-Host "Bumped version: $($result.PreviousVersion) -> $($result.NewVersion) ($($result.BumpType)) from $($result.CommitCount) commit(s)."
    }
    else {
        Write-Host "No version change required ($($result.CommitCount) commit(s), bump type: none)."
    }

    # --- Machine-parseable output contract (do not change key names) ---
    Write-Output "PREVIOUS_VERSION=$($result.PreviousVersion)"
    Write-Output "BUMP_TYPE=$($result.BumpType)"
    Write-Output "NEW_VERSION=$($result.NewVersion)"
    Write-Output "CHANGED=$($result.Changed.ToString().ToLowerInvariant())"

    # --- GitHub Actions integration (no-ops outside CI) ---
    if ($env:GITHUB_OUTPUT) {
        @(
            "previous_version=$($result.PreviousVersion)"
            "new_version=$($result.NewVersion)"
            "bump_type=$($result.BumpType)"
            "changed=$($result.Changed.ToString().ToLowerInvariant())"
        ) | Add-Content -Path $env:GITHUB_OUTPUT
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        $summary = @(
            "## Semantic Version Bump"
            ""
            "| Field | Value |"
            "| --- | --- |"
            "| Previous version | ``$($result.PreviousVersion)`` |"
            "| New version | ``$($result.NewVersion)`` |"
            "| Bump type | $($result.BumpType) |"
            "| Commits considered | $($result.CommitCount) |"
        )
        if ($result.ChangelogEntry) {
            $summary += @("", "### Changelog entry", "", '```markdown', $result.ChangelogEntry.TrimEnd(), '```')
        }
        $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    }

    exit 0
}
catch {
    # Surface a meaningful message and fail the step.
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}
