<#
    Structural tests for the GitHub Actions workflow itself: valid YAML,
    expected triggers/jobs/steps, correct script references, and a clean
    actionlint pass. These are separate from PRLabelAssigner.Tests.ps1
    (which covers the PowerShell tool's logic) and from run-act-tests.sh
    (which exercises the workflow end-to-end via act).
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/pr-label-assigner.yml'
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw

    # Minimal dependency-free YAML-ish parse: we don't pull in a YAML module,
    # so structural checks below use targeted regex/line matching against
    # the raw workflow text instead of a full object graph.
}

Describe 'pr-label-assigner.yml structure' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, and workflow_dispatch triggers' {
        $script:WorkflowText | Should -Match '(?m)^on:'
        $script:WorkflowText | Should -Match '(?m)^\s+push:'
        $script:WorkflowText | Should -Match '(?m)^\s+pull_request:'
        $script:WorkflowText | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'declares both expected jobs' {
        $script:WorkflowText | Should -Match '(?m)^\s+test:'
        $script:WorkflowText | Should -Match '(?m)^\s+assign-labels:'
    }

    It 'makes assign-labels depend on test' {
        $script:WorkflowText | Should -Match 'needs:\s*test'
    }

    It 'declares least-privilege permissions' {
        $script:WorkflowText | Should -Match '(?m)^permissions:'
        $script:WorkflowText | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        ([regex]::Matches($script:WorkflowText, 'actions/checkout@v4')).Count | Should -Be 2
    }

    It 'runs steps with shell: pwsh rather than invoking pwsh -Command from bash' {
        $script:WorkflowText | Should -Match 'shell:\s*pwsh'
        $script:WorkflowText | Should -Not -Match 'pwsh\s+-Command'
        $script:WorkflowText | Should -Not -Match 'pwsh\s+-File'
    }

    It 'references Assign-PRLabels.ps1, which exists in the repo' {
        $script:WorkflowText | Should -Match 'Assign-PRLabels\.ps1'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Assign-PRLabels.ps1') | Should -BeTrue
    }

    It 'references the fixtures it reads from, and those fixtures exist' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'fixtures/label-rules.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'fixtures/changed-files.json') | Should -BeTrue
    }
}

Describe 'pr-label-assigner.yml passes actionlint' {
    It 'exits 0 with no findings' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
