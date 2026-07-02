<#
.SYNOPSIS
    CLI entry point for the PR label assigner.

.DESCRIPTION
    Reads a mocked PR changed-file list (one repo-relative path per line)
    and a JSON ruleset mapping glob patterns to labels, then prints the
    resolved label set. The last line of output is always machine-parseable:

        FINAL LABELS: <comma-separated sorted labels>   (or '(none)')

    which is what the GitHub Actions workflow and the act-based test
    harness assert on.

.EXAMPLE
    ./Invoke-LabelAssigner.ps1 -ChangedFilesPath fixtures/changed-files.txt `
                               -RulesPath fixtures/label-rules.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ChangedFilesPath,

    [Parameter(Mandatory)]
    [string]$RulesPath
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LabelAssigner.psm1') -Force

# --- Load inputs, failing early with actionable messages -------------------
if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
    throw "Changed-files list not found: '$ChangedFilesPath'."
}
if (-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
    throw "Rules file not found: '$RulesPath'."
}

# Blank lines are tolerated so the fixture files can stay human-friendly.
$changedFiles = @(Get-Content -LiteralPath $ChangedFilesPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

try {
    $rules = @(Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json)
}
catch {
    throw "Rules file '$RulesPath' is not valid JSON: $($_.Exception.Message)"
}

# --- Resolve and report -----------------------------------------------------
$labels = @(Get-PRLabels -ChangedFiles $changedFiles -Rules $rules)

Write-Output "Changed files evaluated: $($changedFiles.Count)"
foreach ($label in $labels) {
    Write-Output "label: $label"
}

if ($labels.Count -gt 0) {
    Write-Output "FINAL LABELS: $($labels -join ',')"
}
else {
    Write-Output 'FINAL LABELS: (none)'
}
