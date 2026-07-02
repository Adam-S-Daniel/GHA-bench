# Structure tests for the GitHub Actions workflow file.
#
# These verify (without running Docker):
#   - the workflow exists and has the expected triggers, jobs, and steps
#   - every script/fixture path the workflow references actually exists
#   - actionlint passes (exit code 0)
#
# YAML is checked with targeted string/regex assertions rather than a YAML
# module, so the test has no external dependencies inside the act container.

BeforeAll {
    $script:repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:workflowPath = Join-Path $repoRoot '.github' 'workflows' 'environment-matrix-generator.yml'
    $script:workflow     = if (Test-Path $workflowPath) { Get-Content $workflowPath -Raw } else { '' }
}

Describe 'workflow file structure' {
    It 'exists at .github/workflows/environment-matrix-generator.yml' {
        Test-Path $script:workflowPath | Should -BeTrue
    }

    It 'triggers on push, pull_request and workflow_dispatch' {
        $script:workflow | Should -Match '(?m)^on:'
        $script:workflow | Should -Match '(?m)^\s+push:'
        $script:workflow | Should -Match '(?m)^\s+pull_request:'
        $script:workflow | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'declares least-privilege permissions' {
        $script:workflow | Should -Match '(?m)^permissions:'
        $script:workflow | Should -Match 'contents:\s*read'
    }

    It 'defines the expected jobs with dependencies' {
        $script:workflow | Should -Match '(?m)^\s{2}unit-tests:'
        $script:workflow | Should -Match '(?m)^\s{2}generate-matrix:'
        $script:workflow | Should -Match '(?m)^\s{2}consume-matrix:'
        # generate-matrix must wait for unit tests; consume-matrix for generation.
        $script:workflow | Should -Match '(?ms)generate-matrix:.*?needs:\s*unit-tests'
        $script:workflow | Should -Match '(?ms)consume-matrix:.*?needs:\s*generate-matrix'
    }

    It 'uses actions/checkout@v4 and shell: pwsh on run steps' {
        $script:workflow | Should -Match 'uses:\s*actions/checkout@v4'
        $script:workflow | Should -Match 'shell:\s*pwsh'
        # PowerShell must not be invoked from bash (v3 pitfall).
        $script:workflow | Should -Not -Match 'pwsh\s+-(File|Command)'
    }

    It 'consumes the generated matrix via fromJSON' {
        $script:workflow | Should -Match 'fromJSON\(needs\.generate-matrix\.outputs\.matrix\)'
    }

    It 'references only script and fixture paths that exist in the repo' {
        # Pull every repo-relative path mentioned in the workflow and verify it.
        $refs = [regex]::Matches($script:workflow, '(?<path>(src|tests|fixtures)/[\w./-]+)') |
            ForEach-Object { $_.Groups['path'].Value } | Sort-Object -Unique
        $refs.Count | Should -BeGreaterThan 0
        foreach ($ref in $refs) {
            Test-Path (Join-Path $script:repoRoot $ref) | Should -BeTrue -Because "workflow references '$ref'"
        }
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $lint = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($lint -join "`n")
    }
}
