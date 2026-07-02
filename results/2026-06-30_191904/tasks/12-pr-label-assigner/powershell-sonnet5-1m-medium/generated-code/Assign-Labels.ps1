<#
    .SYNOPSIS
        Computes GitHub PR labels for a set of changed files based on
        configurable glob-pattern rules, and prints them as a JSON array.

    .DESCRIPTION
        Intended to run as a GitHub Actions step. Reads the changed-files
        list from a JSON file (so the file list can be mocked in tests
        instead of requiring a real PR diff), applies the label rules from
        a JSON config file, and prints the resulting label set as JSON.
        When run inside GitHub Actions ($env:GITHUB_OUTPUT is set), also
        writes a "labels=<json>" line so downstream steps/jobs can consume
        the result.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ChangedFilesPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/LabelAssigner.psm1" -Force

if (-not (Test-Path -LiteralPath $ChangedFilesPath)) {
    throw "Changed files list not found at '$ChangedFilesPath'."
}

try {
    $changedFiles = @(Get-Content -LiteralPath $ChangedFilesPath -Raw | ConvertFrom-Json)
}
catch {
    throw "Failed to parse changed files list '$ChangedFilesPath' as JSON: $($_.Exception.Message)"
}

$rules = Import-LabelRules -Path $ConfigPath
$labels = Get-PRLabels -Files ([string[]]$changedFiles) -Rules $rules

$json = ConvertTo-Json -InputObject @($labels) -Compress

if ($env:GITHUB_OUTPUT) {
    "labels=$json" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}

Write-Output $json
