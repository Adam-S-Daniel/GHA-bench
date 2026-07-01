<#
    Assign-PRLabels.ps1

    CLI entry point: reads a (mocked or real) changed-file list and a set of
    path-to-label rules, both as JSON, resolves the final label set via
    PRLabelAssigner.psm1, prints it, and - when running inside GitHub
    Actions - writes it to $GITHUB_OUTPUT for downstream steps/jobs.

    Both inputs default to the repo's fixture files so the script is
    runnable standalone with `pwsh ./Assign-PRLabels.ps1` for local testing.
#>

param(
    [string]$ChangedFilesPath = (Join-Path $PSScriptRoot 'fixtures/changed-files.json'),
    [string]$RulesPath = (Join-Path $PSScriptRoot 'fixtures/label-rules.json')
)

Import-Module (Join-Path $PSScriptRoot 'PRLabelAssigner.psm1') -Force

if (-not (Test-Path -LiteralPath $ChangedFilesPath)) {
    throw "Assign-PRLabels: changed-files list not found at '$ChangedFilesPath'."
}

if (-not (Test-Path -LiteralPath $RulesPath)) {
    throw "Assign-PRLabels: rules file not found at '$RulesPath'."
}

$changedFiles = @(Get-Content -LiteralPath $ChangedFilesPath -Raw | ConvertFrom-Json)
$rules = @(Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json)

Write-Output "Changed files: $($changedFiles -join ', ')"

$labels = Get-PRLabels -ChangedFiles $changedFiles -Rules $rules
$joined = $labels -join ', '

Write-Output "Final Labels: $joined"

if ($env:GITHUB_OUTPUT) {
    "labels=$joined" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
