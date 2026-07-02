#Requires -Modules Pester
<#
    Structural tests for the GitHub Actions workflow file itself: checks
    triggers/jobs/steps, that referenced script paths exist, and that
    actionlint passes cleanly.
#>

BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/environment-matrix-generator.yml'
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'environment-matrix-generator.yml structure' {

    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -Be $true
    }

    It 'declares the expected trigger events' {
        $script:WorkflowText | Should -Match 'push:'
        $script:WorkflowText | Should -Match 'pull_request:'
        $script:WorkflowText | Should -Match 'workflow_dispatch:'
        $script:WorkflowText | Should -Match 'schedule:'
    }

    It 'declares the test, generate-matrix, and build jobs' {
        $script:WorkflowText | Should -Match '(?m)^\s*test:'
        $script:WorkflowText | Should -Match '(?m)^\s*generate-matrix:'
        $script:WorkflowText | Should -Match '(?m)^\s*build:'
    }

    It 'wires generate-matrix as a dependency of build via needs' {
        $script:WorkflowText | Should -Match 'needs:\s*generate-matrix'
    }

    It 'wires test as a dependency of generate-matrix via needs' {
        $script:WorkflowText | Should -Match 'needs:\s*test'
    }

    It 'declares read-only top-level permissions' {
        $script:WorkflowText | Should -Match '(?m)^permissions:'
        $script:WorkflowText | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4' {
        $script:WorkflowText | Should -Match 'actions/checkout@v4'
    }

    It 'uses shell: pwsh for all run steps' {
        $script:WorkflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references the CLI entry script and the file exists on disk' {
        $script:WorkflowText | Should -Match 'src/Generate-Matrix\.ps1'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'src/Generate-Matrix.ps1') | Should -Be $true
    }

    It 'references a matrix config fixture and the file exists on disk' {
        $script:WorkflowText | Should -Match 'fixtures/ci-config\.json'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'fixtures/ci-config.json') | Should -Be $true
    }

    It 'references the tests directory for the Pester run step and it exists on disk' {
        $script:WorkflowText | Should -Match 'Invoke-Pester -Path tests/'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'tests') | Should -Be $true
    }
}

Describe 'environment-matrix-generator.yml passes actionlint' {

    It 'exits 0 with no findings' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
