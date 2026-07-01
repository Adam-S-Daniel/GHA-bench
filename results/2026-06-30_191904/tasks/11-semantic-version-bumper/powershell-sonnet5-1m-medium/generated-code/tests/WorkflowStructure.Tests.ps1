# Structural tests for the GitHub Actions workflow itself: valid triggers,
# jobs, step references to real files, and a clean actionlint run.
BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..'
    $script:workflowPath = Join-Path $repoRoot '.github' 'workflows' 'semantic-version-bumper.yml'
    $script:workflowText = Get-Content -Path $workflowPath -Raw
}

Describe 'Workflow file structure' {
    It 'exists at .github/workflows/semantic-version-bumper.yml' {
        Test-Path -Path $workflowPath | Should -Be $true
    }

    It 'triggers on push, pull_request, and workflow_dispatch' {
        $workflowText | Should -Match '(?m)^on:'
        $workflowText | Should -Match '(?m)^\s*push:'
        $workflowText | Should -Match '(?m)^\s*pull_request:'
        $workflowText | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'declares explicit read permissions' {
        $workflowText | Should -Match '(?m)^permissions:'
        $workflowText | Should -Match 'contents:\s*read'
    }

    It 'defines a test job and a bump-version job with a needs dependency' {
        $workflowText | Should -Match '(?m)^\s*test:'
        $workflowText | Should -Match '(?m)^\s*bump-version:'
        $workflowText | Should -Match 'needs:\s*test'
    }

    It 'uses actions/checkout@v4 and shell: pwsh for its run steps' {
        $workflowText | Should -Match 'actions/checkout@v4'
        $workflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references scripts and paths that actually exist in the repo' {
        $repoRoot = Join-Path $PSScriptRoot '..'
        Test-Path (Join-Path $repoRoot 'scripts' 'Bump-Version.ps1') | Should -Be $true
        Test-Path (Join-Path $repoRoot 'scripts' 'VersionBumper.psm1') | Should -Be $true
        Test-Path (Join-Path $repoRoot 'tests') | Should -Be $true
        Test-Path (Join-Path $repoRoot 'version.json') | Should -Be $true
        Test-Path (Join-Path $repoRoot 'commits.txt') | Should -Be $true
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        & actionlint $workflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
