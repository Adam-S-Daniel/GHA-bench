# Structural tests for the GitHub Actions workflow: valid YAML shape,
# correct references to project files, and a clean actionlint pass.

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/.github/workflows/dependency-license-checker.yml"
    $script:WorkflowText = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'dependency-license-checker.yml workflow' {

    It 'exists at the expected path' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        $WorkflowText | Should -Match 'on:'
        $WorkflowText | Should -Match 'push:'
        $WorkflowText | Should -Match 'pull_request:'
        $WorkflowText | Should -Match 'workflow_dispatch:'
        $WorkflowText | Should -Match 'schedule:'
    }

    It 'declares read-only contents permissions' {
        $WorkflowText | Should -Match 'permissions:'
        $WorkflowText | Should -Match 'contents:\s*read'
    }

    It 'defines a unit-tests job and a license-check job with a dependency between them' {
        $WorkflowText | Should -Match 'unit-tests:'
        $WorkflowText | Should -Match 'license-check:'
        $WorkflowText | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4' {
        $WorkflowText | Should -Match 'actions/checkout@v4'
    }

    It 'runs steps with shell: pwsh' {
        $WorkflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references the Pester test file that exists in the repo' {
        $WorkflowText | Should -Match 'LicenseChecker\.Tests\.ps1'
        Test-Path -LiteralPath "$PSScriptRoot/LicenseChecker.Tests.ps1" | Should -BeTrue
    }

    It 'references the Invoke-LicenseCheck.ps1 script that exists in the repo' {
        $WorkflowText | Should -Match 'Invoke-LicenseCheck\.ps1'
        Test-Path -LiteralPath "$PSScriptRoot/Invoke-LicenseCheck.ps1" | Should -BeTrue
    }

    It 'references manifest and policy fixture paths that exist in the repo' {
        $WorkflowText | Should -Match 'fixtures/clean-package\.json'
        $WorkflowText | Should -Match 'fixtures/policy\.json'
        Test-Path -LiteralPath "$PSScriptRoot/fixtures/clean-package.json" | Should -BeTrue
        Test-Path -LiteralPath "$PSScriptRoot/fixtures/policy.json" | Should -BeTrue
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
