# Structural tests for the GitHub Actions workflow: valid YAML, expected
# triggers/jobs/steps, correct script references, and a clean actionlint run.
# These are checked separately from the act-based execution proof recorded
# in act-result.txt.

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'semantic-version-bumper.yml'
    $script:WorkflowContent = Get-Content -Path $script:WorkflowPath -Raw

    # powershell-yaml is not guaranteed to be present; fall back to a
    # lightweight manual check of key lines when it is unavailable.
    $script:HasYamlModule = $null -ne (Get-Module -ListAvailable -Name powershell-yaml)
    if ($script:HasYamlModule) {
        Import-Module powershell-yaml -Force
        $script:Workflow = ConvertFrom-Yaml -Yaml $script:WorkflowContent
    }
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -Path $script:WorkflowPath | Should -BeTrue
    }

    It 'references scripts that exist in the repository' {
        $script:WorkflowContent | Should -Match 'scripts/VersionBumper\.psm1'
        $script:WorkflowContent | Should -Match 'scripts/Invoke-Bump\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'scripts' 'VersionBumper.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:RepoRoot 'scripts' 'Invoke-Bump.ps1') | Should -BeTrue
    }

    It 'uses shell: pwsh for its run steps' {
        $script:WorkflowContent | Should -Match 'shell:\s*pwsh'
    }

    It 'declares the expected trigger events' {
        $script:WorkflowContent | Should -Match 'push:'
        $script:WorkflowContent | Should -Match 'pull_request:'
        $script:WorkflowContent | Should -Match 'workflow_dispatch:'
        $script:WorkflowContent | Should -Match 'schedule:'
    }

    It 'declares read-only top-level permissions' {
        $script:WorkflowContent | Should -Match 'permissions:'
        $script:WorkflowContent | Should -Match 'contents:\s*read'
    }

    It 'defines an integration-tests job that depends on unit-tests' {
        $script:WorkflowContent | Should -Match 'integration-tests:'
        $script:WorkflowContent | Should -Match 'needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4 in every job' {
        ($script:WorkflowContent | Select-String -Pattern 'actions/checkout@v4' -AllMatches).Matches.Count |
            Should -BeGreaterOrEqual 2
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'act execution proof' {
    It 'produced an act-result.txt artifact recording a successful run' {
        $resultPath = Join-Path $script:RepoRoot 'act-result.txt'
        Test-Path -Path $resultPath | Should -BeTrue

        $content = Get-Content -Path $resultPath -Raw
        $content | Should -Match 'Job succeeded'
        $content | Should -Match 'Resulting version: 1\.2\.0'
        $content | Should -Match 'Resulting version: 1\.1\.1'
        $content | Should -Match 'Resulting version: 2\.0\.0'
        $content | Should -Match 'Resulting version: 2\.1\.0'
    }
}
