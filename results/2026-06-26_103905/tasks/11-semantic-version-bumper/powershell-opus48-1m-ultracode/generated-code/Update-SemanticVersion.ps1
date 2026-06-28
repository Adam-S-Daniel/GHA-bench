#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bump a semantic version based on Conventional Commit messages, update the
    version file, and prepend a generated changelog entry.

.DESCRIPTION
    The orchestrator ties together the pure helpers in SemVerBumper.psm1:

      1. Read the current version from a plain VERSION file or a package.json.
      2. Collect commit messages - from a delimited mock commit-log fixture
         (-CommitLogPath) or, when omitted, from `git log` since the last tag.
      3. Classify the commits (feat -> minor, fix -> patch, breaking -> major)
         and pick the highest-precedence bump.
      4. Compute the next version, write it back to the version file, and prepend
         a markdown changelog entry to the changelog file.
      5. Emit the result on stdout (PREVIOUS_VERSION / BUMP_TYPE / NEW_VERSION),
         and - when running under GitHub Actions - to $GITHUB_OUTPUT and the job
         step summary.

    With -DryRun no files are modified; the computed version is still reported.

.PARAMETER VersionFile
    Path to the version source: a plain text file (e.g. VERSION) or a package.json.

.PARAMETER CommitLogPath
    Optional path to a mock commit-log fixture. Commits are separated by a line
    containing only "<<<COMMIT>>>". When omitted, `git log` is used.

.PARAMETER ChangelogFile
    Path to the changelog markdown file to update. Defaults to CHANGELOG.md next
    to the version file.

.PARAMETER Date
    Release date for the changelog header (yyyy-MM-dd). Defaults to today.

.PARAMETER DryRun
    Compute and report the next version without writing any files.

.EXAMPLE
    ./Update-SemanticVersion.ps1 -VersionFile VERSION -CommitLogPath commits.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$VersionFile,

    [Parameter()]
    [string]$CommitLogPath,

    [Parameter()]
    [string]$ChangelogFile,

    [Parameter()]
    [string]$Date,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the helper module relative to this script so it works from any CWD.
Import-Module (Join-Path $PSScriptRoot 'SemVerBumper.psm1') -Force

# Append a key=value pair to the GitHub Actions step-output file, if present.
function Write-StepOutput {
    param([string]$Key, [string]$Value)
    if ($env:GITHUB_OUTPUT -and (Test-Path -LiteralPath $env:GITHUB_OUTPUT)) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Key=$Value" -Encoding utf8
    }
}

# Collect commit messages, preferring an explicit fixture over live git history.
function Get-Commits {
    param([string]$LogPath)

    if ($LogPath) {
        # Mock commit-log fixture (deterministic, used by CI and tests).
        return Read-CommitLog -Path $LogPath
    }

    # Fallback: read real history since the most recent tag (or all history when
    # there are no tags). Commits are NUL-separated so multi-line bodies survive.
    $lastTag = & git describe --tags --abbrev=0 2>$null
    $range = if ($LASTEXITCODE -eq 0 -and $lastTag) { "$lastTag..HEAD" } else { 'HEAD' }
    $raw = & git log -z --format=%B $range 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "No commit log was provided (-CommitLogPath) and `git log` failed. Run inside a git repository or pass a commit log fixture."
    }
    if ([string]::IsNullOrEmpty($raw)) { return @() }
    return @(($raw -split "`0") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
}

try {
    # --- 1. Current version -------------------------------------------------
    $previousVersion = Get-CurrentVersion -Path $VersionFile

    # Default the changelog next to the version file when not specified.
    if ([string]::IsNullOrWhiteSpace($ChangelogFile)) {
        $dirName = Split-Path -Parent $VersionFile
        if ([string]::IsNullOrEmpty($dirName)) { $dirName = '.' }
        $ChangelogFile = Join-Path $dirName 'CHANGELOG.md'
    }

    # --- 2. Commits & bump classification ----------------------------------
    $commits = @(Get-Commits -LogPath $CommitLogPath)
    $bumpType = Get-VersionBumpType -Commits $commits

    # --- 3. Next version ----------------------------------------------------
    $newVersion = Get-NextVersion -CurrentVersion $previousVersion -BumpType $bumpType
    $changed = ($bumpType -ne 'none')

    # --- 4. Apply changes (unless dry-run or nothing to do) ----------------
    if ($changed -and -not $DryRun) {
        Update-VersionFile -Path $VersionFile -NewVersion $newVersion
        $entry = New-ChangelogEntry -Version $newVersion -Commits $commits -Date $Date
        Update-Changelog -Path $ChangelogFile -Entry $entry

        # Surface the entry in the GitHub Actions job summary when available.
        if ($env:GITHUB_STEP_SUMMARY -and (Test-Path -LiteralPath $env:GITHUB_STEP_SUMMARY)) {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $entry -Encoding utf8
        }
    }

    # --- 5. Report ----------------------------------------------------------
    if ($DryRun) { Write-Host '(dry-run: no files were modified)' }
    if (-not $changed) {
        Write-Host "No conventional feat/fix/breaking commits found; version is unchanged."
    }

    # The three machine-readable lines go to the success stream (Write-Output) so
    # they are both visible in the CI log and capturable by callers/tests.
    Write-Output "PREVIOUS_VERSION=$previousVersion"
    Write-Output "BUMP_TYPE=$bumpType"
    Write-Output "NEW_VERSION=$newVersion"

    Write-StepOutput -Key 'previous_version' -Value $previousVersion
    Write-StepOutput -Key 'bump_type'        -Value $bumpType
    Write-StepOutput -Key 'new_version'       -Value $newVersion
    Write-StepOutput -Key 'changed'           -Value $changed.ToString().ToLowerInvariant()

    exit 0
}
catch {
    # Graceful, meaningful failure: message to stderr, non-zero exit for CI.
    # -ErrorAction Continue prevents the Stop preference from re-throwing here
    # (which would skip the explicit non-zero exit below).
    Write-Error "semantic-version-bumper failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
