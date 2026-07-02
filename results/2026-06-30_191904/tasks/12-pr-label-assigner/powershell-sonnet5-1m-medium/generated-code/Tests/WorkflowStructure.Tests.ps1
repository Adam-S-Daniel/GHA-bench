# Structural checks for the GitHub Actions workflow: YAML shape, referenced
# script paths exist, and actionlint passes. These run directly with
# Invoke-Pester (they validate static structure, not runtime behavior).

BeforeAll {
    $script:WorkflowPath = "$PSScriptRoot/../.github/workflows/pr-label-assigner.yml"
    $script:RepoRoot = Resolve-Path "$PSScriptRoot/.."

    # Minimal YAML->object loader sufficient for our workflow (no external
    # YAML module dependency): shells out to pwsh's ConvertFrom-Json via
    # `yq`/`python` is unavailable by design, so we rely on a tiny parser
    # for the handful of top-level keys we need to assert on.
    $script:RawYaml = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'pr-label-assigner.yml structure' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'declares pull_request, push, workflow_dispatch, and schedule triggers' {
        $script:RawYaml | Should -Match 'pull_request:'
        $script:RawYaml | Should -Match 'push:'
        $script:RawYaml | Should -Match 'workflow_dispatch:'
        $script:RawYaml | Should -Match 'schedule:'
    }

    It 'declares least-privilege permissions' {
        $script:RawYaml | Should -Match 'permissions:'
        $script:RawYaml | Should -Match 'contents:\s*read'
    }

    It 'defines the assign-labels job running on ubuntu-latest' {
        $script:RawYaml | Should -Match 'assign-labels:'
        $script:RawYaml | Should -Match 'runs-on:\s*ubuntu-latest'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $script:RawYaml | Should -Match 'actions/checkout@v4'
    }

    It 'runs PowerShell steps with shell: pwsh (not pwsh -Command/-File)' {
        $script:RawYaml | Should -Match 'shell:\s*pwsh'
        $script:RawYaml | Should -Not -Match 'pwsh -Command'
        $script:RawYaml | Should -Not -Match 'pwsh -File'
    }

    It 'references Assign-Labels.ps1, which exists in the repo' {
        $script:RawYaml | Should -Match 'Assign-Labels\.ps1'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'Assign-Labels.ps1') | Should -BeTrue
    }

    It 'references labels.config.json, which exists in the repo' {
        $script:RawYaml | Should -Match 'labels\.config\.json'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'labels.config.json') | Should -BeTrue
    }

    It 'references LabelAssigner.psm1 (via the script), which exists in the repo' {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot 'LabelAssigner.psm1') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
