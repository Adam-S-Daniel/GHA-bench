# Pester tests validating the GitHub Actions workflow structure itself
# (as opposed to ArtifactCleanup.Tests.ps1 which tests the PowerShell logic).

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/.github/workflows/artifact-cleanup-script.yml"
    $script:WorkflowContent = Get-Content -Path $script:WorkflowPath -Raw
}

Describe 'artifact-cleanup-script.yml structure' {
    It 'exists' {
        Test-Path $script:WorkflowPath | Should -Be $true
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        $script:WorkflowContent | Should -Match '(?m)^on:'
        $script:WorkflowContent | Should -Match 'push:'
        $script:WorkflowContent | Should -Match 'pull_request:'
        $script:WorkflowContent | Should -Match 'workflow_dispatch:'
        $script:WorkflowContent | Should -Match 'schedule:'
    }

    It 'defines a test job and a cleanup job with a dependency between them' {
        $script:WorkflowContent | Should -Match '(?m)^\s*test:'
        $script:WorkflowContent | Should -Match '(?m)^\s*cleanup:'
        $script:WorkflowContent | Should -Match 'needs:\s*test'
    }

    It 'uses actions/checkout@v4' {
        $script:WorkflowContent | Should -Match 'actions/checkout@v4'
    }

    It 'uses shell: pwsh for run steps' {
        $script:WorkflowContent | Should -Match 'shell:\s*pwsh'
    }

    It 'references ArtifactCleanup.Tests.ps1 and Invoke-ArtifactCleanupScript.ps1, and both files exist' {
        $script:WorkflowContent | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        $script:WorkflowContent | Should -Match 'Invoke-ArtifactCleanupScript\.ps1'

        Test-Path "$PSScriptRoot/ArtifactCleanup.Tests.ps1" | Should -Be $true
        Test-Path "$PSScriptRoot/Invoke-ArtifactCleanupScript.ps1" | Should -Be $true
    }

    It 'declares explicit permissions' {
        $script:WorkflowContent | Should -Match '(?m)^permissions:'
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
