#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    CLI entry point: assign labels to a PR from its changed file list.
.DESCRIPTION
    Reads a newline-delimited list of changed files and a JSON rules config,
    computes the final label set via the PRLabelAssigner module, and prints the
    result in a clearly delimited, machine-parseable form. When run inside
    GitHub Actions it also writes the labels to $GITHUB_OUTPUT.

    Inputs are resolved from parameters, then environment variables, then
    sensible defaults, so the script works both locally and in CI:
      -ChangedFilesPath / $env:CHANGED_FILES_FILE  (default: changed-files.txt)
      -RulesPath        / $env:LABEL_RULES_FILE     (default: config/label-rules.json)
      -FirstMatchWins   / $env:FIRST_MATCH_WINS=true
.EXAMPLE
    ./Invoke-LabelAssigner.ps1 -ChangedFilesPath fixtures/changed-files.txt
#>
[CmdletBinding()]
param(
    [string] $ChangedFilesPath,
    [string] $RulesPath,
    [switch] $FirstMatchWins
)

# Stop on any error so failures surface clearly (and fail the CI step).
$ErrorActionPreference = 'Stop'

try {
    # Import the core module relative to this script so it works from any CWD.
    $modulePath = Join-Path $PSScriptRoot 'PRLabelAssigner.psm1'
    Import-Module $modulePath -Force

    # Resolve inputs: parameter > environment variable > default.
    if (-not $ChangedFilesPath) {
        $ChangedFilesPath = if ($env:CHANGED_FILES_FILE) { $env:CHANGED_FILES_FILE } else { 'changed-files.txt' }
    }
    if (-not $RulesPath) {
        $RulesPath = if ($env:LABEL_RULES_FILE) { $env:LABEL_RULES_FILE } else { 'config/label-rules.json' }
    }
    if (-not $FirstMatchWins -and $env:FIRST_MATCH_WINS -eq 'true') {
        $FirstMatchWins = [switch]$true
    }

    if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
        throw "Changed files list not found: '$ChangedFilesPath'."
    }

    # Read the changed files, trimming whitespace and dropping blank/comment lines.
    $changedFiles = Get-Content -LiteralPath $ChangedFilesPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }

    Write-Host "Changed files ($(@($changedFiles).Count)):"
    foreach ($f in $changedFiles) { Write-Host "  - $f" }

    $rules = Import-LabelRules -Path $RulesPath
    Write-Host "Loaded $(@($rules).Count) label rule(s) from '$RulesPath'."

    $labels = @(Get-PRLabels -ChangedFiles @($changedFiles) -Rules $rules -FirstMatchWins:$FirstMatchWins)

    # Emit a clearly delimited, deterministic block the test harness can parse.
    $joined = ($labels -join ', ')
    Write-Host '----- PR LABELS BEGIN -----'
    Write-Host "LABELS: $joined"
    Write-Host "LABEL_COUNT: $(@($labels).Count)"
    Write-Host '----- PR LABELS END -----'

    # When running in GitHub Actions, expose the labels as a step output.
    if ($env:GITHUB_OUTPUT) {
        "labels=$joined"            | Add-Content -LiteralPath $env:GITHUB_OUTPUT
        "label_count=$(@($labels).Count)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }

    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
