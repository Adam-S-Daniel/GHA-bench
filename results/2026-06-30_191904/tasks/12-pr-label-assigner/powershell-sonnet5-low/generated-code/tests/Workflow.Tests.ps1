# Pester tests validating the GitHub Actions workflow structure itself,
# independent of actually executing it via act.

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/../.github/workflows/pr-label-assigner.yml"
    $script:WorkflowYaml = Get-Content -Path $script:WorkflowPath -Raw
}

Describe "PR Label Assigner workflow - structure" {

    It "workflow file exists" {
        Test-Path -Path $script:WorkflowPath | Should -BeTrue
    }

    It "defines push, pull_request, workflow_dispatch and schedule triggers" {
        $script:WorkflowYaml | Should -Match '(?m)^on:'
        $script:WorkflowYaml | Should -Match 'push:'
        $script:WorkflowYaml | Should -Match 'pull_request:'
        $script:WorkflowYaml | Should -Match 'workflow_dispatch:'
        $script:WorkflowYaml | Should -Match 'schedule:'
    }

    It "declares read contents and write pull-requests permissions" {
        $script:WorkflowYaml | Should -Match 'contents:\s*read'
        $script:WorkflowYaml | Should -Match 'pull-requests:\s*write'
    }

    It "defines both the unit-tests and assign-labels jobs" {
        $script:WorkflowYaml | Should -Match '(?m)^\s*unit-tests:'
        $script:WorkflowYaml | Should -Match '(?m)^\s*assign-labels:'
    }

    It "makes assign-labels depend on unit-tests" {
        $script:WorkflowYaml | Should -Match 'needs:\s*unit-tests'
    }

    It "uses actions/checkout@v4" {
        $script:WorkflowYaml | Should -Match 'actions/checkout@v4'
    }

    It "uses shell: pwsh for run steps" {
        $script:WorkflowYaml | Should -Match 'shell:\s*pwsh'
    }

    It "references the label assigner script and test suite files that exist on disk" {
        $script:WorkflowYaml | Should -Match 'Invoke-LabelAssigner\.ps1'
        $script:WorkflowYaml | Should -Match 'LabelAssigner\.Tests\.ps1'

        Test-Path -Path "$PSScriptRoot/../src/Invoke-LabelAssigner.ps1" | Should -BeTrue
        Test-Path -Path "$PSScriptRoot/../src/LabelAssigner.ps1" | Should -BeTrue
        Test-Path -Path "$PSScriptRoot/../tests/LabelAssigner.Tests.ps1" | Should -BeTrue
    }

    It "references fixture files that exist on disk" {
        Test-Path -Path "$PSScriptRoot/../fixtures/case1-docs-and-api.json" | Should -BeTrue
        Test-Path -Path "$PSScriptRoot/../fixtures/case2-priority-conflict.json" | Should -BeTrue
    }
}

Describe "PR Label Assigner workflow - actionlint validation" {

    It "passes actionlint with exit code 0" {
        $actionlintPath = (Get-Command actionlint -ErrorAction SilentlyContinue).Source
        if (-not $actionlintPath) {
            Set-ItResult -Skipped -Because "actionlint is not installed on this machine"
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
