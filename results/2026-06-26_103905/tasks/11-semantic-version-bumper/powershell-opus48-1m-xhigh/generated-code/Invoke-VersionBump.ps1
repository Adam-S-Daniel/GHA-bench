#Requires -Version 7.0

<#
.SYNOPSIS
    Bump a project's semantic version from Conventional Commit messages.

.DESCRIPTION
    Orchestrates the SemanticVersionBumper module to:
      1. read the current version from a VERSION file or package.json,
      2. read commit messages from a commit-log file,
      3. decide the bump (feat -> minor, fix -> patch, breaking -> major),
      4. compute and write back the new version,
      5. prepend a changelog entry,
      6. emit the new version.

    Designed to run inside a GitHub Actions step. It prints machine-readable
    "KEY=VALUE" lines to stdout and, when running under Actions, also writes to
    $GITHUB_OUTPUT and the step summary so later steps/jobs can consume them.

.PARAMETER VersionFile
    Path to the version source (VERSION file or package.json). Default: ./VERSION.

.PARAMETER CommitsFile
    Path to the commit log fixture (one commit per line, or "---"-separated
    multi-line records). Default: ./commits.txt.

.PARAMETER ChangelogFile
    Path to the changelog to update/create. Default: ./CHANGELOG.md.

.PARAMETER Date
    Date stamp used in the changelog entry (yyyy-MM-dd). Defaults to today.
    Exposed so tests / CI can produce deterministic output.

.PARAMETER NoWrite
    When set, computes everything and prints results but does not modify any
    files (a dry run).

.OUTPUTS
    Exit code 0 on success, 1 on any handled error.
    stdout lines: PREVIOUS_VERSION=, BUMP_TYPE=, NEW_VERSION=, CHANGED=.
#>
[CmdletBinding()]
param(
    [string] $VersionFile   = 'VERSION',
    [string] $CommitsFile   = 'commits.txt',
    [string] $ChangelogFile = 'CHANGELOG.md',
    [string] $Date          = (Get-Date -Format 'yyyy-MM-dd'),
    [switch] $NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module that sits next to this script.
$modulePath = Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1'
Import-Module $modulePath -Force

# Helper: write a KEY=VALUE pair to GITHUB_OUTPUT when running under Actions.
function Write-GitHubOutput {
    param([string] $Name, [string] $Value)
    if ($env:GITHUB_OUTPUT -and (Test-Path -LiteralPath $env:GITHUB_OUTPUT)) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
}

try {
    # --- 1. current version ------------------------------------------------
    $current = Get-CurrentVersion -Path $VersionFile

    # --- 2. commit messages ------------------------------------------------
    # Wrap in @() so a single commit stays an array (the pipeline would
    # otherwise unroll a one-element array to a scalar string).
    $commits = @(Get-CommitsFromFile -Path $CommitsFile)

    # --- 3. decide bump ----------------------------------------------------
    $bumpType = Get-VersionBumpType -Commits $commits

    # --- 4. compute next version ------------------------------------------
    $next    = Get-NextVersion -Version $current -BumpType $bumpType
    $changed = ($next -ne $current)

    Write-Host "Analyzed $($commits.Count) commit(s)."
    Write-Host "PREVIOUS_VERSION=$current"
    Write-Host "BUMP_TYPE=$bumpType"
    Write-Host "NEW_VERSION=$next"
    Write-Host "CHANGED=$($changed.ToString().ToLowerInvariant())"

    if ($changed -and -not $NoWrite) {
        # --- 5. write new version + changelog ------------------------------
        Update-VersionFile -Path $VersionFile -NewVersion $next
        $entry = New-ChangelogEntry -Version $next -Commits $commits -Date $Date
        Add-ChangelogEntry -Path $ChangelogFile -Entry $entry
        Write-Host "Updated '$VersionFile' and '$ChangelogFile'."
    } elseif (-not $changed) {
        Write-Host 'No conventional commits warranted a version bump; nothing changed.'
    } else {
        Write-Host 'Dry run (-NoWrite): files were not modified.'
    }

    # Machine-readable outputs for downstream steps/jobs.
    Write-GitHubOutput -Name 'previous-version' -Value $current
    Write-GitHubOutput -Name 'new-version'      -Value $next
    Write-GitHubOutput -Name 'bump-type'        -Value $bumpType
    Write-GitHubOutput -Name 'changed'          -Value ($changed.ToString().ToLowerInvariant())

    # Human-friendly step summary when running under Actions.
    if ($env:GITHUB_STEP_SUMMARY -and (Test-Path -LiteralPath $env:GITHUB_STEP_SUMMARY)) {
        @(
            '### Semantic Version Bumper',
            '',
            "- Previous version: ``$current``",
            "- Bump type: **$bumpType**",
            "- New version: ``$next``"
        ) -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }

    exit 0
}
catch {
    # Graceful, meaningful error reporting.
    Write-Host "ERROR: $($_.Exception.Message)"
    [Console]::Error.WriteLine("semantic-version-bumper failed: $($_.Exception.Message)")
    exit 1
}
