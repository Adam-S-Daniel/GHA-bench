# Structural tests for the GitHub Actions workflow itself: YAML shape,
# referenced script paths, and actionlint validation.

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'test-results-aggregator.yml'
    $script:WorkflowYaml = Get-Content -LiteralPath $WorkflowPath -Raw

    # Minimal YAML -> object parse without an external module: powershell-yaml
    # isn't guaranteed to be present, so rely on ConvertFrom-Json via a tiny
    # yq-free approach is overkill here — instead assert on the raw text,
    # which is sufficient to verify structure for this fixed-shape file.
}

Describe 'test-results-aggregator.yml structure' {
    It 'exists' {
        Test-Path -LiteralPath $WorkflowPath | Should -Be $true
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        $WorkflowYaml | Should -Match 'on:'
        $WorkflowYaml | Should -Match 'push:'
        $WorkflowYaml | Should -Match 'pull_request:'
        $WorkflowYaml | Should -Match 'workflow_dispatch:'
        $WorkflowYaml | Should -Match 'schedule:'
    }

    It 'declares read-only top-level permissions' {
        $WorkflowYaml | Should -Match 'permissions:\s*\n\s*contents:\s*read'
    }

    It 'defines the unit-tests and aggregate jobs with a dependency between them' {
        $WorkflowYaml | Should -Match 'unit-tests:'
        $WorkflowYaml | Should -Match 'aggregate:'
        $WorkflowYaml | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses shell: pwsh for its run steps' {
        $WorkflowYaml | Should -Match 'shell:\s*pwsh'
    }

    It 'references Invoke-Aggregation.ps1, which exists in the repo' {
        $WorkflowYaml | Should -Match 'Invoke-Aggregation\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'Invoke-Aggregation.ps1') | Should -Be $true
    }

    It 'references the Pester test file, which exists in the repo' {
        $WorkflowYaml | Should -Match 'tests/Aggregator\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'tests' 'Aggregator.Tests.ps1') | Should -Be $true
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
