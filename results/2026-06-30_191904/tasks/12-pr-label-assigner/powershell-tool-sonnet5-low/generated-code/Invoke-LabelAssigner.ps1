<#
    Invoke-LabelAssigner.ps1

    CLI entry point for the PR Label Assigner. Reads a (mocked) list of
    changed file paths and a JSON rules configuration, computes the final
    label set, prints it as a comma-separated string, and — when run
    inside GitHub Actions — writes it to $GITHUB_OUTPUT as `labels`.
#>
param(
    [Parameter(Mandatory)][string]$ChangedFilesPath,
    [Parameter(Mandatory)][string]$RulesPath
)

$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/PrLabelAssigner.psm1" -Force

if (-not (Test-Path -LiteralPath $ChangedFilesPath)) {
    throw "Invoke-LabelAssigner: changed-files list not found at path '$ChangedFilesPath'."
}

$changedFiles = Get-Content -LiteralPath $ChangedFilesPath | Where-Object { $_.Trim() -ne '' }
if (-not $changedFiles -or $changedFiles.Count -eq 0) {
    throw "Invoke-LabelAssigner: changed-files list at '$ChangedFilesPath' is empty."
}

$rules = Import-PrLabelRules -Path $RulesPath
$labels = Get-PrLabels -ChangedFiles $changedFiles -Rules $rules

$labelString = $labels -join ','
Write-Output $labelString

if ($env:GITHUB_OUTPUT) {
    "labels=$labelString" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
