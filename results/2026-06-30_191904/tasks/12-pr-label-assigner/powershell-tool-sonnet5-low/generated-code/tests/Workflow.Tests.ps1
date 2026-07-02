# Structural tests for the GitHub Actions workflow: valid YAML, expected
# triggers/jobs/steps, correct script references, and a clean actionlint run.

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/../.github/workflows/pr-label-assigner.yml"
    $script:WorkflowContent = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'pr-label-assigner.yml - structure' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, and workflow_dispatch triggers' {
        $WorkflowContent | Should -Match 'on:'
        $WorkflowContent | Should -Match 'push:'
        $WorkflowContent | Should -Match 'pull_request:'
        $WorkflowContent | Should -Match 'workflow_dispatch:'
    }

    It 'defines a test job and an assign-labels job with a job dependency' {
        $WorkflowContent | Should -Match 'test:'
        $WorkflowContent | Should -Match 'assign-labels:'
        $WorkflowContent | Should -Match 'needs:\s*test'
    }

    It 'declares explicit permissions' {
        $WorkflowContent | Should -Match 'permissions:'
        $WorkflowContent | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4' {
        $WorkflowContent | Should -Match 'actions/checkout@v4'
    }

    It 'runs steps with shell: pwsh' {
        $WorkflowContent | Should -Match 'shell:\s*pwsh'
    }

    It 'references the Invoke-LabelAssigner.ps1 script that exists on disk' {
        $WorkflowContent | Should -Match 'Invoke-LabelAssigner\.ps1'
        Test-Path -LiteralPath "$PSScriptRoot/../Invoke-LabelAssigner.ps1" | Should -BeTrue
    }

    It 'references a rules JSON fixture that exists on disk' {
        $WorkflowContent | Should -Match 'fixtures/label-rules\.json'
        Test-Path -LiteralPath "$PSScriptRoot/../fixtures/label-rules.json" | Should -BeTrue
    }
}

Describe 'pr-label-assigner.yml - actionlint validation' {
    It 'passes actionlint with a clean exit code' {
        $actionlintCmd = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlintCmd) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
