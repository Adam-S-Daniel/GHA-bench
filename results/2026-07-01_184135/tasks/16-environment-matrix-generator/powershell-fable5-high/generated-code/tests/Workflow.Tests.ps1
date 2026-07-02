<#
.SYNOPSIS
    Structure tests for .github/workflows/environment-matrix-generator.yml.

.DESCRIPTION
    Verifies (without Docker):
      - the workflow file exists and has the expected structure
        (triggers, jobs, steps, shell: pwsh usage)
      - every script/fixture path the workflow references actually exists
      - actionlint passes (exit code 0)
    YAML structure is checked textually plus via actionlint, which performs a
    full YAML + expression parse - so a malformed document cannot sneak past.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'environment-matrix-generator.yml'
    $script:Workflow = if (Test-Path $WorkflowPath) { Get-Content $WorkflowPath -Raw } else { '' }
}

Describe 'Workflow file structure' {
    It 'exists at .github/workflows/environment-matrix-generator.yml' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request and workflow_dispatch triggers' {
        $Workflow | Should -Match '(?m)^on:'
        $Workflow | Should -Match '(?m)^\s+push:'
        $Workflow | Should -Match '(?m)^\s+pull_request:'
        $Workflow | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'restricts permissions to contents: read' {
        $Workflow | Should -Match '(?m)^permissions:'
        $Workflow | Should -Match '(?m)^\s+contents:\s*read'
    }

    It 'defines the test, generate-matrix and consume-matrix jobs' {
        $Workflow | Should -Match '(?m)^\s{2}test:'
        $Workflow | Should -Match '(?m)^\s{2}generate-matrix:'
        $Workflow | Should -Match '(?m)^\s{2}consume-matrix:'
    }

    It 'chains the jobs with needs so they run in order' {
        $Workflow | Should -Match '(?m)^\s+needs:\s*test'
        $Workflow | Should -Match '(?m)^\s+needs:\s*generate-matrix'
    }

    It 'uses actions/checkout@v4' {
        $Workflow | Should -Match 'uses:\s*actions/checkout@v4'
    }

    It 'uses shell: pwsh on run steps (PowerShell mode requirement)' {
        $Workflow | Should -Match 'shell:\s*pwsh'
        # No bash-wrapped pwsh invocations anywhere.
        $Workflow | Should -Not -Match 'pwsh\s+-(Command|File)'
    }

    It 'consumes the generated matrix via fromJSON' {
        $Workflow | Should -Match 'matrix:\s*\$\{\{\s*fromJSON\('
    }
}

Describe 'Workflow file references' {
    It 'references the entry script, and that script exists' {
        $Workflow | Should -Match 'Invoke-MatrixGenerator\.ps1'
        Test-Path (Join-Path $RepoRoot 'Invoke-MatrixGenerator.ps1') | Should -BeTrue
    }

    It 'references the CI fixture config, and that fixture exists' {
        $Workflow | Should -Match 'fixtures/ci-config\.json'
        Test-Path (Join-Path $RepoRoot 'fixtures' 'ci-config.json') | Should -BeTrue
    }

    It 'runs the Pester unit-test suite, and that suite exists' {
        $Workflow | Should -Match 'tests/MatrixGenerator\.Tests\.ps1'
        Test-Path (Join-Path $RepoRoot 'tests' 'MatrixGenerator.Tests.ps1') | Should -BeTrue
    }

    It 'the src library referenced by the entry script exists' {
        Test-Path (Join-Path $RepoRoot 'src' 'MatrixGenerator.ps1') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
