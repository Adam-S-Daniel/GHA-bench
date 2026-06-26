#!/usr/bin/env pwsh
# Assign-Labels.ps1
#
# CLI entry point used by the GitHub Actions workflow. It loads the rules and
# the (mocked) changed-files list, computes the labels, and prints the
# machine-parseable FINAL_LABELS / LABEL_COUNT lines that CI asserts on.
#
# Usage:
#   pwsh ./Assign-Labels.ps1 -RulesPath ./fixtures/rules.json `
#                            -ChangedFilesPath ./fixtures/changed-files.txt

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RulesPath,
    [Parameter(Mandatory)] [string] $ChangedFilesPath
)

$ErrorActionPreference = 'Stop'

# Load the library functions next to this script.
. "$PSScriptRoot/PRLabelAssigner.ps1"

try {
    Invoke-PRLabelAssigner -RulesPath $RulesPath -ChangedFilesPath $ChangedFilesPath | Out-Null
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
