#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assigns labels to a set of changed files based on configurable
    path-to-label glob rules. This is the CLI entry point used by the
    GitHub Actions workflow.

.DESCRIPTION
    Loads label rules from a JSON config and a changed-file manifest (the
    "mock file list"), resolves the final label set (supporting glob
    patterns, multiple labels per file, priority ordering, and exclusive
    rules), and prints a report. The last two report lines are machine
    parseable:
        PR_LABELS=<comma-separated, priority-ordered>
        PR_LABEL_COUNT=<n>

    When running inside GitHub Actions the labels are also written to
    $GITHUB_OUTPUT (as 'labels') and appended to the job step summary.

.PARAMETER RulesPath
    Path to the JSON rules config. Defaults to fixtures/label-rules.json
    relative to this script.

.PARAMETER ChangedFilesPath
    Path to the changed-files manifest (one path per line). Defaults to
    fixtures/changed-files.txt relative to this script.

.EXAMPLE
    ./Invoke-PrLabelAssigner.ps1 -RulesPath rules.json -ChangedFilesPath files.txt
#>
[CmdletBinding()]
param(
    [string]$RulesPath,
    [string]$ChangedFilesPath
)

# Stop on any uncaught error so failures surface as a non-zero exit code in CI.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    # Resolve defaults relative to this script so the tool works from any CWD.
    $scriptDir = $PSScriptRoot
    if (-not $RulesPath) { $RulesPath = Join-Path $scriptDir 'fixtures/label-rules.json' }
    if (-not $ChangedFilesPath) { $ChangedFilesPath = Join-Path $scriptDir 'fixtures/changed-files.txt' }

    Import-Module (Join-Path $scriptDir 'src/PrLabelAssigner.psm1') -Force

    $rules = Import-LabelRules -Path $RulesPath
    $files = Get-ChangedFile -Path $ChangedFilesPath

    $result = Resolve-PrLabels -ChangedFiles $files -Rules $rules
    $report = Format-PrLabelOutput -Result $result

    # Emit the report to stdout (captured by act / CI logs).
    $report | ForEach-Object { Write-Output $_ }

    # Surface results to GitHub Actions if available (no-op locally).
    $labelCsv = $result.Labels -join ','
    if ($env:GITHUB_OUTPUT) {
        "labels=$labelCsv"            | Add-Content -Path $env:GITHUB_OUTPUT
        "count=$($result.Labels.Count)" | Add-Content -Path $env:GITHUB_OUTPUT
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        "## PR labels`n`n``$labelCsv``" | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    }

    exit 0
}
catch {
    # Graceful, meaningful error reporting with a non-zero exit code.
    Write-Error "pr-label-assigner failed: $($_.Exception.Message)"
    exit 1
}
