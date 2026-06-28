#Requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point for the PR Label Assigner — used by the GitHub Actions
    workflow and runnable standalone.

.DESCRIPTION
    Reads a mock changed-file list and a rule config, resolves the label set,
    and emits it in a deterministic, machine-parseable form:

        LABELS=<comma-separated labels in priority order>

    When running inside GitHub Actions (or `act`) it also:
        - appends `labels=<...>` to the file named by $env:GITHUB_OUTPUT
        - appends a small markdown table to $env:GITHUB_STEP_SUMMARY

    Exit codes:
        0  success
        1  a handled error (missing/invalid config or file list)

.PARAMETER ChangedFilesPath
    Path to a text file listing changed paths, one per line. This is the
    "mock the PR file list" hook.

.PARAMETER ConfigPath
    Path to the JSON rules config (pattern -> labels, priority, stop).

.EXAMPLE
    pwsh ./Invoke-PrLabelAssigner.ps1 `
        -ChangedFilesPath fixtures/changed-files.txt `
        -ConfigPath config/labels.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ChangedFilesPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Import the resolution module that lives alongside this script. Using
    # $PSScriptRoot keeps it working regardless of the caller's CWD.
    $modulePath = Join-Path $PSScriptRoot 'PrLabelAssigner.psm1'
    Import-Module $modulePath -Force

    $labels = @(Resolve-PrLabel -ChangedFilesPath $ChangedFilesPath -ConfigPath $ConfigPath)
    $joined = ($labels -join ',')

    # Primary machine-parseable line consumed by the test harness / next steps.
    Write-Host "LABELS=$joined"

    # Human-friendly echo of the inputs and result.
    Write-Host "Resolved $($labels.Count) label(s) for the changed file set."

    # GitHub Actions step output (so downstream jobs/steps can `needs`/use it).
    if ($env:GITHUB_OUTPUT) {
        "labels=$joined" | Add-Content -Path $env:GITHUB_OUTPUT -Encoding utf8
    }

    # GitHub Actions job summary (nice rendering in the run UI).
    if ($env:GITHUB_STEP_SUMMARY) {
        $summary = @(
            '### PR Label Assigner'
            ''
            "**Labels applied:** $(if ($labels.Count) { $joined } else { '_none_' })"
        ) -join "`n"
        $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
    }

    exit 0
}
catch {
    # Graceful, meaningful error reporting on stderr; non-zero exit fails the job.
    Write-Error "PR Label Assigner failed: $($_.Exception.Message)"
    exit 1
}
