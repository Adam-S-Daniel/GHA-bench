# Structure tests for the GitHub Actions workflow.
# Written first (red) in TDD cycle 6, before the workflow file existed.
# Text-based assertions are used (no YAML module dependency) plus an
# actionlint gate when the tool is available (it is on dev machines and in
# the harness; inside the act container the check is skipped).

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'artifact-cleanup-script.yml'
    $script:WorkflowText = if (Test-Path $script:WorkflowPath) {
        Get-Content $script:WorkflowPath -Raw
    } else { '' }
}

Describe 'artifact-cleanup-script.yml workflow' {

    It 'exists' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'triggers on push, pull_request, schedule and workflow_dispatch' {
        $script:WorkflowText | Should -Match '(?m)^\s*push:'
        $script:WorkflowText | Should -Match '(?m)^\s*pull_request:'
        $script:WorkflowText | Should -Match '(?m)^\s*schedule:'
        $script:WorkflowText | Should -Match '(?m)^\s*workflow_dispatch:'
    }

    It 'defines the expected jobs with a dependency between them' {
        $script:WorkflowText | Should -Match '(?m)^\s*pester-tests:'
        $script:WorkflowText | Should -Match '(?m)^\s*cleanup-plan:'
        $script:WorkflowText | Should -Match '(?m)^\s*needs:\s*pester-tests'
    }

    It 'restricts permissions to read-only contents' {
        $script:WorkflowText | Should -Match '(?m)^\s*permissions:'
        $script:WorkflowText | Should -Match '(?m)^\s*contents:\s*read'
    }

    It 'uses actions/checkout@v4 and pwsh shells' {
        $script:WorkflowText | Should -Match 'actions/checkout@v4'
        $script:WorkflowText | Should -Match 'shell:\s*pwsh'
        # No bash-wrapped pwsh invocations (they cause escaping issues in act).
        $script:WorkflowText | Should -Not -Match 'pwsh\s+-Command'
        $script:WorkflowText | Should -Not -Match 'pwsh\s+-File'
    }

    It 'references script files that actually exist in the repo' {
        # Every repo-relative .ps1/.psm1/.json path mentioned in the workflow
        # must exist, so the workflow cannot drift from the codebase.
        $refs = [regex]::Matches($script:WorkflowText, '[\w./-]+\.(?:ps1|psm1|json)') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        $refs | Should -Not -BeNullOrEmpty
        foreach ($ref in $refs) {
            (Test-Path (Join-Path $script:RepoRoot $ref)) | Should -BeTrue -Because "workflow references '$ref'"
        }
    }

    It 'passes actionlint with exit code 0' {
        if (-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment (checked on host and in the harness)'
            return
        }
        actionlint $script:WorkflowPath | Out-String | Write-Verbose
        $LASTEXITCODE | Should -Be 0
    }
}
