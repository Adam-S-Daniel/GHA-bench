<#
.SYNOPSIS
    Assigns PR labels based on a changed-file list and a glob-based rules
    config, and prints/exports the final label set.

.DESCRIPTION
    This is the CLI entry point used by the GitHub Actions workflow. In a
    real PR trigger, ChangedFilesPath would be produced by a prior step
    (e.g. tj-actions/changed-files); here it defaults to a checked-in JSON
    fixture so the tool is trivially mockable for local runs, Pester tests,
    and act.

.PARAMETER ChangedFilesPath
    Path to a JSON file containing an array of changed file paths.

.PARAMETER RulesPath
    Path to a JSON file containing the label rules (see label-rules.json).
#>
[CmdletBinding()]
param(
    [string]$ChangedFilesPath = (Join-Path $PSScriptRoot 'changed-files.json'),
    [string]$RulesPath = (Join-Path $PSScriptRoot 'label-rules.json')
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LabelAssigner.psm1') -Force

if (-not (Test-Path -Path $ChangedFilesPath -PathType Leaf)) {
    throw "Changed files fixture not found at path: '$ChangedFilesPath'. Provide -ChangedFilesPath pointing to a JSON array of file paths."
}

try {
    $changedFiles = @(Get-Content -Path $ChangedFilesPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}
catch {
    throw "Failed to parse changed files fixture '$ChangedFilesPath': $($_.Exception.Message)"
}

$rules = Import-LabelRules -Path $RulesPath
$labels = @(Get-PrLabels -ChangedFiles $changedFiles -Rules $rules)

# Written via the success/output stream (not Write-Host) so this is both
# capturable by callers (Pester, `act` log parsing) and still visible in
# the Actions job log.
Write-Output "Changed files ($($changedFiles.Count)):"
foreach ($file in $changedFiles) {
    Write-Output "  - $file"
}
Write-Output ''

if ($labels.Count -gt 0) {
    Write-Output "Final labels: $($labels -join ', ')"
}
else {
    Write-Output 'Final labels: (none)'
}

if ($env:GITHUB_OUTPUT) {
    "labels=$($labels -join ',')" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

if ($env:GITHUB_STEP_SUMMARY) {
    @(
        '## PR Label Assignment'
        ''
        "Changed files: $($changedFiles.Count)"
        ''
        "Labels: $($labels -join ', ')"
    ) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
