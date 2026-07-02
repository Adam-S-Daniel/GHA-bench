# Invoke-LabelAssigner.ps1
# CLI entry point used by the GitHub Actions workflow. Reads a JSON fixture
# describing changed files and label rules, computes the final label set,
# and prints it (one label per line, plus a summary line) for the workflow
# to capture.

param(
    [Parameter(Mandatory)]
    [string] $FixturePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $FixturePath)) {
    throw "Fixture file not found: $FixturePath"
}

. "$PSScriptRoot/LabelAssigner.ps1"

$fixture = Get-Content -Path $FixturePath -Raw | ConvertFrom-Json

if (-not $fixture.changedFiles) {
    throw "Fixture must define 'changedFiles'."
}
if (-not $fixture.rules) {
    throw "Fixture must define 'rules'."
}

$changedFiles = @($fixture.changedFiles)

$rules = @()
foreach ($r in $fixture.rules) {
    $rules += @{
        Pattern  = $r.pattern
        Label    = $r.label
        Priority = if ($null -ne $r.priority) { [int]$r.priority } else { 0 }
    }
}

$labels = Get-PrLabels -ChangedFiles $changedFiles -Rules $rules

Write-Output "CASE: $($fixture.name)"
if ($labels -and $labels.Count -gt 0) {
    Write-Output "LABELS: $($labels -join ',')"
} else {
    Write-Output "LABELS: (none)"
}
