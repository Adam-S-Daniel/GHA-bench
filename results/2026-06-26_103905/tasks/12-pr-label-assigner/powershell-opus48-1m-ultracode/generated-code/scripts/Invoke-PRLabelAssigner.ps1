#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CLI wrapper around the PR Label Assigner module for a single PR.

.DESCRIPTION
    Reads a "changed files" list and a labeler config, resolves the final label
    set, and prints it. The label set is printed both human-readably and as a
    single machine-parseable line:

        RESULT case=<name> labels=<comma,separated|NONE>

    When the GITHUB_OUTPUT environment variable is present (i.e. running inside a
    GitHub Actions / act step) the labels are also written there as a step output
    named 'labels', so downstream jobs could apply them to a real PR.

.PARAMETER ChangedFilesPath
    Path to a file containing one changed path per line (the mock PR file list).

.PARAMETER ConfigPath
    Path to the JSON labeler config.

.PARAMETER CaseName
    Optional label for this run (used in the RESULT line). Defaults to the
    changed-files file's base name with any leading "case-" stripped.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ChangedFilesPath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [string]$CaseName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module relative to this script so the CLI works from any CWD.
Import-Module (Join-Path $PSScriptRoot '..' 'src' 'PRLabelAssigner.psm1') -Force

try {
    if (-not $PSBoundParameters.ContainsKey('CaseName') -or [string]::IsNullOrWhiteSpace($CaseName)) {
        $CaseName = [System.IO.Path]::GetFileNameWithoutExtension($ChangedFilesPath) -replace '^case-', ''
    }

    $rules        = Import-LabelConfig -Path $ConfigPath
    $changedFiles = Get-ChangedFileList -Path $ChangedFilesPath
    $labels       = Get-PRLabels -ChangedFiles $changedFiles -Rules $rules

    $labelText = if ($labels -and $labels.Count -gt 0) { $labels -join ',' } else { 'NONE' }

    # Human-readable summary (information stream; ends up in the CI log).
    Write-Host "PR Label Assigner -- case '$CaseName'"
    Write-Host ("  Changed files : {0}" -f (($changedFiles -join ', ') -replace '^$', '(none)'))
    Write-Host ("  Final labels  : {0}" -f $labelText)

    # Machine-parseable line the test harness asserts against.
    Write-Host ("RESULT case={0} labels={1}" -f $CaseName, $labelText)

    # Expose as a GitHub Actions step output when available.
    if ($env:GITHUB_OUTPUT) {
        "labels=$($labels -join ',')" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }

    # Return the array so callers within PowerShell can consume it directly.
    return , [string[]]$labels
}
catch {
    Write-Error "PR Label Assigner failed: $($_.Exception.Message)"
    exit 1
}
