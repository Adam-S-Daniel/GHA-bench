# Workflow.Tests.ps1
#
# TDD cycle 6: structural tests for the GitHub Actions workflow. Written
# red-first (before the workflow file existed). These are lightweight
# structural assertions on the YAML source; full syntactic validation is
# delegated to actionlint, whose exit code is asserted below when the tool
# is available (locally and in CI runners that ship it — inside the act
# container the actionlint check is skipped rather than failed).

BeforeAll {
    $script:workflowPath = Join-Path $PSScriptRoot '..' '.github' 'workflows' 'pr-label-assigner.yml'
    $script:repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Test-Path $workflowPath) {
        $script:yaml = Get-Content -LiteralPath $workflowPath -Raw
    }
}

Describe 'pr-label-assigner.yml workflow structure' {

    It 'exists at .github/workflows/pr-label-assigner.yml' {
        Test-Path $workflowPath | Should -BeTrue
    }

    Context 'triggers' {
        It 'triggers on push' {
            $yaml | Should -Match '(?m)^\s*push:'
        }

        It 'triggers on pull_request' {
            $yaml | Should -Match '(?m)^\s*pull_request:'
        }

        It 'supports manual runs via workflow_dispatch' {
            $yaml | Should -Match '(?m)^\s*workflow_dispatch:'
        }
    }

    Context 'jobs and dependencies' {
        It "defines a 'test' job" {
            $yaml | Should -Match '(?m)^\s{2}test:'
        }

        It "defines an 'assign-labels' job" {
            $yaml | Should -Match '(?m)^\s{2}assign-labels:'
        }

        It "'assign-labels' depends on 'test'" {
            $yaml | Should -Match '(?m)^\s*needs:\s*test\b'
        }

        It 'declares least-privilege permissions' {
            $yaml | Should -Match '(?m)^permissions:'
            $yaml | Should -Match '(?m)^\s*contents:\s*read'
        }
    }

    Context 'steps' {
        It 'checks out the repository with actions/checkout@v4' {
            $yaml | Should -Match 'uses:\s*actions/checkout@v4'
        }

        It 'runs PowerShell steps with shell: pwsh' {
            $yaml | Should -Match '(?m)^\s*shell:\s*pwsh'
        }

        It 'runs the Pester suite in the test job' {
            $yaml | Should -Match 'Invoke-Pester'
        }
    }

    Context 'script references point at real files' {
        It 'references src/Invoke-LabelAssigner.ps1, which exists' {
            $yaml | Should -Match 'src/Invoke-LabelAssigner\.ps1'
            Test-Path (Join-Path $repoRoot 'src' 'Invoke-LabelAssigner.ps1') | Should -BeTrue
        }

        It 'references the fixtures the label job consumes, which exist' {
            $yaml | Should -Match 'fixtures/changed-files\.txt'
            $yaml | Should -Match 'fixtures/label-rules\.json'
            Test-Path (Join-Path $repoRoot 'fixtures' 'changed-files.txt') | Should -BeTrue
            Test-Path (Join-Path $repoRoot 'fixtures' 'label-rules.json') | Should -BeTrue
        }
    }

    Context 'actionlint validation' {
        It 'passes actionlint with exit code 0' {
            if (-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'actionlint is not installed in this environment (e.g. inside the act container)'
                return
            }
            $output = actionlint $workflowPath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "actionlint should report no issues, got: $output"
        }
    }
}
