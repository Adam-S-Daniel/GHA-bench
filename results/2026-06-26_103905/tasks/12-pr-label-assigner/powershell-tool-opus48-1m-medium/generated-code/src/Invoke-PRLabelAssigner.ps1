#!/usr/bin/env pwsh
<#
    Invoke-PRLabelAssigner.ps1

    CLI entrypoint that wires the PRLabelAssigner module into a CI pipeline.

    It reads:
      * a JSON file of label rules           (-RulesPath)
      * a newline-delimited list of changed files (-ChangedFilesPath)

    ...and prints the resolved label set. Two output lines are emitted so the
    result is easy to consume both by humans and by downstream automation:

        LABELS: api,tests,source          <- comma-joined, ordered by priority
        LABEL_COUNT: 3

    When -GitHubOutput is supplied (or the GITHUB_OUTPUT env var is set), the
    same values are also written in `key=value` form to that file so a workflow
    can expose them as step outputs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RulesPath,

    [Parameter(Mandatory)]
    [string] $ChangedFilesPath,

    [string] $GitHubOutput = $env:GITHUB_OUTPUT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import the module that lives alongside this script.
$modulePath = Join-Path $PSScriptRoot 'PRLabelAssigner.psm1'
Import-Module $modulePath -Force

try {
    # --- Load rules -------------------------------------------------------
    $rules = Import-LabelRules -Path $RulesPath

    # --- Load changed files ----------------------------------------------
    if (-not (Test-Path -LiteralPath $ChangedFilesPath -PathType Leaf)) {
        throw "Changed-files list not found: '$ChangedFilesPath'."
    }

    # Read the file list, trimming blank lines and surrounding whitespace.
    $changedFiles = @(
        Get-Content -LiteralPath $ChangedFilesPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )

    Write-Host "Evaluating $($changedFiles.Count) changed file(s) against $($rules.Count) rule(s)."

    # --- Resolve labels ---------------------------------------------------
    $labels = @(Get-PRLabels -ChangedFiles $changedFiles -Rules $rules)

    $joined = $labels -join ','
    Write-Host "LABELS: $joined"
    Write-Host "LABEL_COUNT: $($labels.Count)"

    # --- Emit GitHub Actions step outputs --------------------------------
    if ($GitHubOutput) {
        "labels=$joined"            | Add-Content -LiteralPath $GitHubOutput
        "label_count=$($labels.Count)" | Add-Content -LiteralPath $GitHubOutput
    }

    exit 0
}
catch {
    # Surface a clear, single-line error and fail the step.
    Write-Error "PR label assignment failed: $($_.Exception.Message)"
    exit 1
}
