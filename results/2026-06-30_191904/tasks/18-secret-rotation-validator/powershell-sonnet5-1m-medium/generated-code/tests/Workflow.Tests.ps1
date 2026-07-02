# Structural tests for the GitHub Actions workflow: valid YAML, expected
# triggers/jobs/steps, correct script references, and a clean actionlint run.

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/../.github/workflows/secret-rotation-validator.yml"
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml -Yaml $script:WorkflowText
}

Describe 'Workflow file structure' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -Be $true
    }

    It 'parses as valid YAML' {
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'declares push, pull_request, schedule, and workflow_dispatch triggers' {
        # YAML parses the bareword key "on" as boolean True.
        $onKey = if ($script:Workflow.ContainsKey('on')) { 'on' } else { 'True' }
        $triggers = $script:Workflow[$onKey]

        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines a validate job that checks out the repo and sets up pwsh steps' {
        $script:Workflow.jobs.Keys | Should -Contain 'validate'
        $steps = $script:Workflow.jobs.validate.steps
        ($steps | Where-Object { $_.uses -like 'actions/checkout@*' }) | Should -Not -BeNullOrEmpty
    }

    It 'declares explicit permissions' {
        $script:Workflow.ContainsKey('permissions') | Should -Be $true
    }

    It 'references the validator script and test files that exist on disk' {
        $repoRoot = "$PSScriptRoot/.."
        $script:WorkflowText | Should -Match 'Invoke-Validator\.ps1'
        $script:WorkflowText | Should -Match 'Invoke-Pester'

        Test-Path "$repoRoot/Invoke-Validator.ps1" | Should -Be $true
        Test-Path "$repoRoot/src/SecretRotationValidator.psm1" | Should -Be $true
        Test-Path "$repoRoot/tests/SecretRotationValidator.Tests.ps1" | Should -Be $true
    }
}

Describe 'actionlint' {
    It 'passes with no errors on the workflow file' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
