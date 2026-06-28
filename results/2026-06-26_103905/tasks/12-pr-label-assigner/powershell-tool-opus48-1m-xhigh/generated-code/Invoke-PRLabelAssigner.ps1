#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI entry point for the PR Label Assigner. Reads a rules config and a list
    of changed files, prints the resolved label set, and (in GitHub Actions)
    publishes the labels as a step output and job summary.

.DESCRIPTION
    Resolution order for the changed-file list:
      1. -ChangedFiles parameter, if supplied.
      2. otherwise the file at -ChangedFilesPath (one path per line; blank lines
         and '#' comments are ignored).

    The script frames the resolved labels between LABELS_BEGIN / LABELS_END
    marker lines so a CI harness (or `act`) can extract the EXACT, ordered set
    from the step log without guessing. It also prints a compact
    LABELS_RESULT=[...] line for humans.

.PARAMETER RulesPath
    Path to the JSON rules config. Defaults to $env:RULES_FILE or
    'labeler-rules.json'.

.PARAMETER ChangedFilesPath
    Path to a newline-delimited list of changed files. Defaults to
    $env:CHANGED_FILES_FILE or 'fixtures/changed-files.txt'.

.PARAMETER ChangedFiles
    Explicit changed-file list; overrides ChangedFilesPath when provided.

.EXAMPLE
    ./Invoke-PRLabelAssigner.ps1 -RulesPath labeler-rules.json -ChangedFilesPath fixtures/changed-files.txt
#>
[CmdletBinding()]
param(
    [string]   $RulesPath        = $(if ($env:RULES_FILE)         { $env:RULES_FILE }         else { 'labeler-rules.json' }),
    [string]   $ChangedFilesPath = $(if ($env:CHANGED_FILES_FILE) { $env:CHANGED_FILES_FILE } else { 'fixtures/changed-files.txt' }),
    [string[]] $ChangedFiles
)

$ErrorActionPreference = 'Stop'

# Import the engine from the script's own directory so the script works no
# matter what the current working directory is.
Import-Module (Join-Path $PSScriptRoot 'PRLabelAssigner.psm1') -Force

# --- Resolve the changed-file list. ------------------------------------------
if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
    if (-not (Test-Path -LiteralPath $ChangedFilesPath)) {
        throw "Changed-files list not found: '$ChangedFilesPath'. " +
              "Pass -ChangedFiles, -ChangedFilesPath, or set `$env:CHANGED_FILES_FILE."
    }
    $ChangedFiles = @(
        Get-Content -LiteralPath $ChangedFilesPath |
            ForEach-Object { $_.Trim() } |
            Where-Object   { $_ -and -not $_.StartsWith('#') }
    )
}

# --- Load rules and compute labels. ------------------------------------------
$rules  = Import-LabelRule -Path $RulesPath
$labels = @(Get-PRLabel -ChangedFiles $ChangedFiles -Rules $rules)

# --- Emit a machine-parseable frame plus a human-readable summary line. ------
Write-Output 'LABELS_BEGIN'
foreach ($label in $labels) { Write-Output $label }
Write-Output 'LABELS_END'
Write-Output ("LABELS_RESULT=[" + ($labels -join ', ') + "]")

# --- Publish to GitHub Actions when running inside a workflow. ----------------
if ($env:GITHUB_OUTPUT) {
    "labels=$($labels -join ',')" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}
if ($env:GITHUB_STEP_SUMMARY) {
    $summary = if ($labels.Count -gt 0) {
        "## PR labels`n`n" + (($labels | ForEach-Object { "- $_" }) -join "`n") + "`n"
    }
    else {
        "## PR labels`n`n_No labels matched the changed files._`n"
    }
    $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
}
