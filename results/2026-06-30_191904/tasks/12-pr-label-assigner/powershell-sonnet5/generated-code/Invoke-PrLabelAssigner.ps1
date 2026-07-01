<#
    Invoke-PrLabelAssigner.ps1

    CI entry point: computes the PR label set from a changed-file list and a
    path-to-label rule config, then reports the result to the console, the
    GitHub Actions job summary, and $GITHUB_OUTPUT (for downstream steps).

    Changed-file resolution (see Get-PrChangedFiles in PrLabelAssigner.psm1):
      - If -FixturePath exists, its contents are used verbatim. This is how
        the 'push'-triggered CI path (and the act-based test harness) mocks
        a PR's file list without needing real GitHub API access.
      - Otherwise, -BaseRef/-HeadRef are diffed with git (the real
        'pull_request' event path).
#>
[CmdletBinding()]
param(
    [string]$RulesPath = (Join-Path $PSScriptRoot 'rules.json'),
    [string]$FixturePath = (Join-Path $PSScriptRoot 'changed-files.txt'),
    [string]$BaseRef,
    [string]$HeadRef = 'HEAD'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PrLabelAssigner.psm1') -Force

try {
    $rules = Import-PrLabelRules -Path $RulesPath
    $changedFiles = Get-PrChangedFiles -FixturePath $FixturePath -BaseRef $BaseRef -HeadRef $HeadRef
    $labels = Resolve-PrLabels -ChangedFiles $changedFiles -Rules $rules
} catch {
    Write-Error "PR label assignment failed: $($_.Exception.Message)"
    exit 1
}

Write-Host "Changed files ($($changedFiles.Count)):"
foreach ($file in $changedFiles) {
    Write-Host "  - $file"
}

Write-Host ''
Write-Host "FINAL_LABELS=$($labels -join ',')"

if ($env:GITHUB_OUTPUT) {
    "labels=$($labels -join ',')" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

if ($env:GITHUB_STEP_SUMMARY) {
    $summaryLines = @(
        '## PR Label Assignment'
        ''
        "**Changed files:** $($changedFiles.Count)"
        ''
    )
    if ($labels.Count -gt 0) {
        $summaryLines += '**Labels:**'
        $summaryLines += @($labels | ForEach-Object { "- ``$_``" })
    } else {
        $summaryLines += '_No labels matched._'
    }
    ($summaryLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
