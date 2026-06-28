<#
.SYNOPSIS
    CLI entry point for the semantic version bumper, used both locally and by
    the GitHub Actions workflow.

.DESCRIPTION
    Dot-sources SemanticVersionBumper.ps1 (the testable function library) and
    runs Invoke-VersionBump against the supplied files. Emits machine-readable
    output for CI:

        NEW_VERSION=<x.y.z>     (stdout, easy to grep/assert on)
        BUMP_TYPE=<type>

    and, when $env:GITHUB_OUTPUT is set, also writes those to the GitHub Actions
    step-output file so downstream steps/jobs can consume them.

.EXAMPLE
    pwsh ./Invoke-Bump.ps1 -VersionFile version.txt -CommitLogFile commits.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $VersionFile,
    [Parameter(Mandatory)] [string] $CommitLogFile,
    [string] $ChangelogFile = 'CHANGELOG.md',
    [string] $Date,
    [switch] $FailOnNoBump
)

# Fail fast on any unhandled error so CI surfaces problems clearly.
$ErrorActionPreference = 'Stop'

# Load the function library that sits next to this script.
. (Join-Path $PSScriptRoot 'SemanticVersionBumper.ps1')

try {
    $bumpArgs = @{
        VersionFile   = $VersionFile
        CommitLogFile = $CommitLogFile
        ChangelogFile = $ChangelogFile
    }
    if ($Date)         { $bumpArgs.Date = $Date }
    if ($FailOnNoBump) { $bumpArgs.FailOnNoBump = $true }

    $result = Invoke-VersionBump @bumpArgs

    # Human-readable summary.
    Write-Host "Old version:  $($result.OldVersion)"
    Write-Host "Bump type:    $($result.BumpType)"
    Write-Host "New version:  $($result.NewVersion)"

    # Machine-readable lines the CI harness asserts on (EXACT values).
    Write-Host "NEW_VERSION=$($result.NewVersion)"
    Write-Host "BUMP_TYPE=$($result.BumpType)"

    # GitHub Actions step outputs (no-op locally when the var is unset).
    if ($env:GITHUB_OUTPUT) {
        "new_version=$($result.NewVersion)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
        "bump_type=$($result.BumpType)"     | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }
}
catch {
    Write-Error "Version bump failed: $($_.Exception.Message)"
    exit 1
}
