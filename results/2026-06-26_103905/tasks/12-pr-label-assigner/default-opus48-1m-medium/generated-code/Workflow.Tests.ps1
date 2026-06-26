# Workflow.Tests.ps1
#
# Structural tests for the GitHub Actions workflow. These do NOT run act; they
# verify the workflow file's shape, that it references real script paths, and
# that actionlint validates it cleanly. Run with:
#   pwsh -c "Invoke-Pester ./Workflow.Tests.ps1"

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/pr-label-assigner.yml'
    $script:Yaml         = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'has a name' {
        $Yaml | Should -Match '(?m)^name:\s*PR Label Assigner'
    }
}

Describe 'Triggers' {
    It 'triggers on pull_request' { $Yaml | Should -Match '(?m)^\s*pull_request:' }
    It 'triggers on push'         { $Yaml | Should -Match '(?m)^\s*push:' }
    It 'allows manual dispatch'   { $Yaml | Should -Match '(?m)^\s*workflow_dispatch:' }
}

Describe 'Jobs and dependencies' {
    It 'defines a unit-tests job'    { $Yaml | Should -Match '(?m)^\s*unit-tests:' }
    It 'defines an assign-labels job'{ $Yaml | Should -Match '(?m)^\s*assign-labels:' }
    It 'assign-labels depends on unit-tests (needs)' {
        $Yaml | Should -Match 'needs:\s*unit-tests'
    }
    It 'declares permissions' {
        $Yaml | Should -Match '(?m)^permissions:'
    }
}

Describe 'Steps reference real script files' {
    It 'uses actions/checkout@v4' {
        $Yaml | Should -Match 'uses:\s*actions/checkout@v4'
    }
    It 'invokes Assign-Labels.ps1' {
        $Yaml | Should -Match 'Assign-Labels\.ps1'
    }
    It 'runs the Pester test file' {
        $Yaml | Should -Match 'PRLabelAssigner\.Tests\.ps1'
    }
    It 'all referenced script files exist on disk' {
        foreach ($f in @('PRLabelAssigner.ps1', 'Assign-Labels.ps1', 'PRLabelAssigner.Tests.ps1')) {
            Test-Path -LiteralPath (Join-Path $Root $f) | Should -BeTrue -Because "$f is referenced by the workflow"
        }
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed'; return }
        & actionlint $WorkflowPath 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
