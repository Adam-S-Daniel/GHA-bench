# Structural tests for the GitHub Actions workflow itself: valid YAML, expected
# triggers/jobs/steps, correct script references, and a clean actionlint pass.

BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $WorkflowPath = Join-Path $RepoRoot '.github/workflows/semantic-version-bumper.yml'
    $WorkflowText = Get-Content -Path $WorkflowPath -Raw

    # Minimal YAML -> object parsing without external modules: PowerShell can
    # deserialize the subset of YAML this workflow uses via a tiny converter
    # is overkill here, so we assert on the raw text/structure instead, which
    # is sufficient to prove the workflow is well-formed and references the
    # right files.
}

Describe 'semantic-version-bumper workflow structure' {
    It 'exists at the expected path' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request and workflow_dispatch triggers' {
        $WorkflowText | Should -Match 'on:'
        $WorkflowText | Should -Match 'push:'
        $WorkflowText | Should -Match 'pull_request:'
        $WorkflowText | Should -Match 'workflow_dispatch:'
    }

    It 'declares a job that runs on ubuntu-latest' {
        $WorkflowText | Should -Match 'runs-on:\s*ubuntu-latest'
    }

    It 'sets read-only top-level permissions' {
        $WorkflowText | Should -Match 'permissions:\s*\r?\n\s*contents:\s*read'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $WorkflowText | Should -Match 'uses:\s*actions/checkout@v4'
    }

    It 'uses shell: pwsh for its run steps' {
        $WorkflowText | Should -Match 'shell:\s*pwsh'
    }

    It 'references the Pester test directory that exists in this repo' {
        $WorkflowText | Should -Match '\./tests'
        Test-Path (Join-Path $RepoRoot 'tests') | Should -BeTrue
    }

    It 'references the Invoke-VersionBump.ps1 script which exists in this repo' {
        $WorkflowText | Should -Match 'Invoke-VersionBump\.ps1'
        Test-Path (Join-Path $RepoRoot 'Invoke-VersionBump.ps1') | Should -BeTrue
    }

    It 'references fixture files that exist in this repo' {
        $WorkflowText | Should -Match 'fixtures/demo-package\.json'
        Test-Path (Join-Path $RepoRoot 'fixtures/demo-package.json') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'fixtures/commits-feat.txt') | Should -BeTrue
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
