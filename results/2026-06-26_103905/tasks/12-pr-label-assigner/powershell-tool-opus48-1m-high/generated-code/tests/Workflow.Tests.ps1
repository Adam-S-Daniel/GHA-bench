# Structural tests for the GitHub Actions workflow.
#
# These parse the workflow YAML and assert its shape (triggers, jobs, steps),
# confirm the referenced script files exist, and verify that actionlint passes.
#
# Run with:  Invoke-Pester -Path ./tests/Workflow.Tests.ps1

BeforeAll {
    $script:repoRoot     = Split-Path -Parent $PSScriptRoot
    $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/pr-label-assigner.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:wf = ConvertFrom-Yaml (Get-Content -LiteralPath $script:workflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:workflowPath | Should -BeTrue
    }

    It 'is valid, parseable YAML with a name' {
        $script:wf | Should -Not -BeNullOrEmpty
        $script:wf['name'] | Should -Be 'PR Label Assigner'
    }
}

Describe 'Triggers' {
    # YAML maps the bareword "on" to the boolean $true, so the trigger key may be
    # either the string 'on' or the boolean True depending on the parser.
    BeforeAll {
        $script:triggers = if ($script:wf.ContainsKey('on')) { $script:wf['on'] } else { $script:wf[$true] }
    }

    It 'defines the on/triggers block' {
        $script:triggers | Should -Not -BeNullOrEmpty
    }

    It 'triggers on push (so the act test harness can drive it)' {
        $script:triggers.ContainsKey('push') | Should -BeTrue
    }

    It 'triggers on pull_request' {
        $script:triggers.ContainsKey('pull_request') | Should -BeTrue
    }

    It 'supports manual workflow_dispatch' {
        $script:triggers.ContainsKey('workflow_dispatch') | Should -BeTrue
    }
}

Describe 'Permissions' {
    It 'declares least-privilege permissions' {
        $script:wf['permissions']['contents'] | Should -Be 'read'
        $script:wf['permissions']['pull-requests'] | Should -Be 'write'
    }
}

Describe 'Jobs and steps' {
    It 'defines a test job and an assign-labels job' {
        $script:wf['jobs'].Keys | Should -Contain 'test'
        $script:wf['jobs'].Keys | Should -Contain 'assign-labels'
    }

    It 'wires assign-labels to depend on test' {
        $script:wf['jobs']['assign-labels']['needs'] | Should -Be 'test'
    }

    It 'checks out the repository in every job' {
        foreach ($jobName in $script:wf['jobs'].Keys) {
            $steps = $script:wf['jobs'][$jobName]['steps']
            ($steps.uses -join ' ') | Should -Match 'actions/checkout@v4'
        }
    }

    It 'runs its pwsh steps with shell: pwsh' {
        $runSteps = foreach ($jobName in $script:wf['jobs'].Keys) {
            $script:wf['jobs'][$jobName]['steps'] | Where-Object { $_.ContainsKey('run') }
        }
        $runSteps | Should -Not -BeNullOrEmpty
        foreach ($step in $runSteps) {
            $step['shell'] | Should -Be 'pwsh'
        }
    }
}

Describe 'Script references resolve to real files' {
    It 'references the entry script that exists on disk' {
        $allRun = foreach ($jobName in $script:wf['jobs'].Keys) {
            $script:wf['jobs'][$jobName]['steps'] | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_['run'] }
        }
        ($allRun -join "`n") | Should -Match 'Invoke-LabelAssigner\.ps1'
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'Invoke-LabelAssigner.ps1') | Should -BeTrue
    }

    It 'references the Pester test file that exists on disk' {
        $allRun = foreach ($jobName in $script:wf['jobs'].Keys) {
            $script:wf['jobs'][$jobName]['steps'] | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_['run'] }
        }
        ($allRun -join "`n") | Should -Match 'tests/PRLabelAssigner\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'tests/PRLabelAssigner.Tests.ps1') | Should -BeTrue
    }

    It 'points its env defaults at files that exist' {
        Test-Path -LiteralPath (Join-Path $script:repoRoot $script:wf['env']['CHANGED_FILES_FILE']) | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repoRoot $script:wf['env']['LABEL_RULES_FILE'])   | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        $output = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
