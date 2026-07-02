<#
.SYNOPSIS
    Validates the environment-matrix-generator workflow's structure and
    referenced file paths, and asserts actionlint passes cleanly.
    Run directly with: pwsh ./Test-WorkflowStructure.ps1
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$workflowPath = Join-Path $root '.github/workflows/environment-matrix-generator.yml'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message" -ForegroundColor Red
    } else {
        Write-Host "PASS: $Message" -ForegroundColor Green
    }
}

Assert-True (Test-Path $workflowPath) "workflow file exists at $workflowPath"
$yamlText = Get-Content -Path $workflowPath -Raw

# Basic structural checks without requiring a YAML parser module -- the workflow
# is small and well-formed enough that text/regex checks on known keys are reliable.
Assert-True ($yamlText -match '(?m)^on:') "workflow defines 'on:' triggers"
Assert-True ($yamlText -match 'push:') "workflow triggers on push"
Assert-True ($yamlText -match 'pull_request:') "workflow triggers on pull_request"
Assert-True ($yamlText -match 'workflow_dispatch:') "workflow triggers on workflow_dispatch"
Assert-True ($yamlText -match '(?m)^permissions:') "workflow defines a permissions block"
Assert-True ($yamlText -match 'contents:\s*read') "workflow permissions include contents: read"
Assert-True ($yamlText -match '(?m)^jobs:') "workflow defines jobs"
Assert-True ($yamlText -match 'test-and-generate:') "workflow defines the test-and-generate job"
Assert-True ($yamlText -match 'actions/checkout@v4') "workflow uses actions/checkout@v4"
Assert-True ($yamlText -match "shell:\s*pwsh") "workflow steps use shell: pwsh"
Assert-True ($yamlText -match 'Invoke-Pester') "workflow runs Invoke-Pester"

# Try powershell-yaml for a real parse if it happens to be available; otherwise the
# regex checks above already validated structure, so this block is best-effort.
$hasPowerShellYaml = Get-Module -ListAvailable -Name powershell-yaml
if ($hasPowerShellYaml) {
    Import-Module powershell-yaml
    $parsed = ConvertFrom-Yaml -Yaml $yamlText
    Assert-True ($null -ne $parsed['jobs']['test-and-generate']) "parsed YAML contains test-and-generate job"
    Assert-True ($parsed['jobs']['test-and-generate']['steps'].Count -ge 6) "parsed YAML job has at least 6 steps"
} else {
    Write-Host "INFO: powershell-yaml module not available; relying on text-based structural checks." -ForegroundColor Yellow
}

# Verify referenced script/fixture paths actually exist on disk.
$referencedPaths = @(
    'New-EnvironmentMatrix.ps1',
    'New-EnvironmentMatrix.Tests.ps1',
    'fixtures/basic.json',
    'fixtures/with-include-exclude.json',
    'fixtures/exceeds-max.json'
)
foreach ($relPath in $referencedPaths) {
    $fullPath = Join-Path $root $relPath
    Assert-True (Test-Path $fullPath) "referenced path exists: $relPath"
}

# Verify actionlint passes cleanly.
$actionlintOutput = & actionlint $workflowPath 2>&1
$actionlintExit = $LASTEXITCODE
Assert-True ($actionlintExit -eq 0) "actionlint exits with code 0 (got $actionlintExit; output: $actionlintOutput)"

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "ALL WORKFLOW STRUCTURE CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($failures.Count) WORKFLOW STRUCTURE CHECK(S) FAILED" -ForegroundColor Red
    exit 1
}
