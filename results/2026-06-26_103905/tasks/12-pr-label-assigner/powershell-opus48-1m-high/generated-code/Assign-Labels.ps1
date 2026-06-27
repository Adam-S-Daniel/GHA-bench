#!/usr/bin/env pwsh
# Assign-Labels.ps1
# CLI wrapper around the LabelAssigner module, used by the CI workflow.
#
# It resolves the label set for a list of changed files and emits machine-
# parseable lines on stdout:
#     LABELS=<comma-separated labels, in priority order>
#     LABEL_COUNT=<n>
# When running inside GitHub Actions it also appends `labels`/`count` to the
# step's $GITHUB_OUTPUT so downstream jobs can consume them.
#
# Inputs (parameters take precedence over the matching env vars):
#     -RulesPath        / LABELER_RULES_FILE    (default: rules.json)
#     -ChangedFilesPath / LABELER_CHANGED_FILES (default: fixtures/changed-files.txt)

[CmdletBinding()]
param(
    [string]$RulesPath,
    [string]$ChangedFilesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    # Resolve inputs: explicit parameter > environment variable > default.
    if (-not $RulesPath) {
        $RulesPath = if ($env:LABELER_RULES_FILE) { $env:LABELER_RULES_FILE } else { 'rules.json' }
    }
    if (-not $ChangedFilesPath) {
        $ChangedFilesPath = if ($env:LABELER_CHANGED_FILES) { $env:LABELER_CHANGED_FILES } else { 'fixtures/changed-files.txt' }
    }

    # Import the module relative to this script so it works from any CWD.
    $modulePath = Join-Path $PSScriptRoot 'src/LabelAssigner.psm1'
    Import-Module $modulePath -Force

    Write-Host "Rules file:        $RulesPath"
    Write-Host "Changed-files file: $ChangedFilesPath"

    $result = Invoke-LabelAssigner -ChangedFilesPath $ChangedFilesPath -RulesPath $RulesPath

    $labelList = @($result.Labels)
    $joined = $labelList -join ','

    Write-Host "Changed file count: $(@($result.ChangedFiles).Count)"
    Write-Host "Rule count:         $($result.RuleCount)"

    # Machine-parseable output consumed by the act test harness.
    Write-Host "LABELS=$joined"
    Write-Host "LABEL_COUNT=$($labelList.Count)"

    # Real CI integration: surface the values as step outputs when available.
    if ($env:GITHUB_OUTPUT) {
        "labels=$joined"            | Add-Content -Path $env:GITHUB_OUTPUT
        "count=$($labelList.Count)" | Add-Content -Path $env:GITHUB_OUTPUT
    }

    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
