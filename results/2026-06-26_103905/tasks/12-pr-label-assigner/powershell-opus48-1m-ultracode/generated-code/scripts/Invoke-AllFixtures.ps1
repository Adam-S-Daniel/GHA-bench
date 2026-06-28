#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run the PR Label Assigner over every fixture in a directory.

.DESCRIPTION
    Iterates over fixtures/case-*.txt, resolves labels for each using the shared
    config, and prints one machine-parseable line per case:

        RESULT case=<name> labels=<comma,separated|NONE>

    This is the entry point the GitHub Actions workflow invokes. Bundling all
    fixture cases into a single workflow run lets the test harness exercise every
    case through `act` while keeping the number of (slow) `act push` runs to one.

.PARAMETER FixturesDir
    Directory containing the case-*.txt fixture files.

.PARAMETER ConfigPath
    Path to the JSON labeler config shared by all cases.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FixturesDir,

    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'src' 'PRLabelAssigner.psm1') -Force

try {
    if (-not (Test-Path -LiteralPath $FixturesDir -PathType Container)) {
        throw "Fixtures directory not found: '$FixturesDir'"
    }

    # Load the rules once; every case shares the same config.
    $rules = Import-LabelConfig -Path $ConfigPath

    $fixtures = Get-ChildItem -LiteralPath $FixturesDir -Filter 'case-*.txt' | Sort-Object Name
    if (-not $fixtures -or $fixtures.Count -eq 0) {
        throw "No fixtures (case-*.txt) found in '$FixturesDir'"
    }

    Write-Host "PR Label Assigner -- processing $($fixtures.Count) fixture case(s) from '$FixturesDir'"
    Write-Host ("Using config: {0}" -f $ConfigPath)
    Write-Host ('=' * 60)

    foreach ($fixture in $fixtures) {
        $caseName     = $fixture.BaseName -replace '^case-', ''
        $changedFiles = Get-ChangedFileList -Path $fixture.FullName
        $labels       = Get-PRLabels -ChangedFiles $changedFiles -Rules $rules
        $labelText    = if ($labels -and $labels.Count -gt 0) { $labels -join ',' } else { 'NONE' }

        Write-Host ""
        Write-Host "[case: $caseName]"
        foreach ($f in $changedFiles) { Write-Host "    + $f" }
        Write-Host ("RESULT case={0} labels={1}" -f $caseName, $labelText)
    }

    Write-Host ""
    Write-Host ('=' * 60)
    Write-Host "All fixture cases processed successfully."
}
catch {
    Write-Error "PR Label Assigner (all fixtures) failed: $($_.Exception.Message)"
    exit 1
}
