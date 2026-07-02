<#
.SYNOPSIS
    CLI entry point for the PR Label Assigner.
.DESCRIPTION
    Reads a newline-delimited list of changed file paths (a mock of a PR's
    changed files) and a JSON rules config, computes the label set via the
    LabelAssigner module, and prints:
      * one "  <file> -> <labels>" line per file (diagnostics)
      * a final machine-parseable line: "LABELS: a,b,c" (or "LABELS: (none)")
.EXAMPLE
    ./Invoke-LabelAssigner.ps1 -ChangedFilesPath fixtures/changed-files.txt -RulesPath fixtures/label-rules.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ChangedFilesPath,

    [Parameter(Mandatory)]
    [string]$RulesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LabelAssigner.psm1') -Force

# --- Input validation with meaningful errors -------------------------------
if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
    throw "Changed-files list not found: '$ChangedFilesPath'. Provide a text file with one changed path per line."
}
if (-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
    throw "Rules file not found: '$RulesPath'. Provide a JSON array of { Pattern, Labels[, Priority, Exclusive] } rules."
}

$changedFiles = @(Get-Content -LiteralPath $ChangedFilesPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' })

try {
    $rules = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json
}
catch {
    throw "Rules file '$RulesPath' is not valid JSON: $($_.Exception.Message)"
}
if ($null -eq $rules -or @($rules).Count -eq 0) {
    throw "Rules file '$RulesPath' contains no rules."
}

# --- Compute and report -----------------------------------------------------
$labels = Get-PRLabels -ChangedFiles $changedFiles -Rules @($rules)

Write-Output "Changed files ($($changedFiles.Count)):"
foreach ($f in $changedFiles) {
    $fileLabels = Get-PRLabels -ChangedFiles @($f) -Rules @($rules)
    $shown = if (@($fileLabels).Count) { @($fileLabels) -join ',' } else { '(none)' }
    Write-Output "  $f -> $shown"
}

$final = if (@($labels).Count) { @($labels) -join ',' } else { '(none)' }
Write-Output "LABELS: $final"
