# Workflow-structure tests: parse the YAML, verify triggers/jobs/steps,
# confirm referenced script paths exist, and assert actionlint passes.
# These run on the host (not through act) per the task's structure-test section.

BeforeAll {
    $RepoRoot     = Split-Path $PSScriptRoot -Parent
    $WorkflowPath = Join-Path $RepoRoot '.github/workflows/test-results-aggregator.yml'
    $script:Wf    = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow structure' {
    It 'parses as valid YAML' {
        $Wf | Should -Not -BeNullOrEmpty
    }

    It 'has the expected trigger events' {
        # YAML "on:" is parsed; PowerShell sees it as the key "on".
        $on = $Wf.'on'
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege permissions' {
        $Wf.permissions.contents | Should -Be 'read'
    }

    It 'defines the unit-tests and aggregate jobs' {
        $Wf.jobs.Keys | Should -Contain 'unit-tests'
        $Wf.jobs.Keys | Should -Contain 'aggregate'
    }

    It 'wires job dependency so aggregate needs unit-tests' {
        $Wf.jobs.aggregate.needs | Should -Be 'unit-tests'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($jobName in 'unit-tests', 'aggregate') {
            $uses = $Wf.jobs.$jobName.steps.uses
            ($uses -contains 'actions/checkout@v4') | Should -BeTrue
        }
    }

    It 'runs every run-step with the pwsh shell' {
        foreach ($jobName in $Wf.jobs.Keys) {
            foreach ($step in $Wf.jobs.$jobName.steps) {
                if ($step.run) { $step.shell | Should -Be 'pwsh' }
            }
        }
    }
}

Describe 'Workflow references existing files' {
    It 'references the aggregation entry script which exists' {
        $runText = ($Wf.jobs.aggregate.steps | ForEach-Object { $_.run }) -join "`n"
        $runText | Should -Match 'Invoke-Aggregation\.ps1'
        Test-Path (Join-Path $RepoRoot 'Invoke-Aggregation.ps1') | Should -BeTrue
    }

    It 'references the Pester test file which exists' {
        $runText = ($Wf.jobs.'unit-tests'.steps | ForEach-Object { $_.run }) -join "`n"
        $runText | Should -Match 'tests/TestResultsAggregator\.Tests\.ps1'
        Test-Path (Join-Path $RepoRoot 'tests/TestResultsAggregator.Tests.ps1') | Should -BeTrue
    }

    It 'ships the module the script depends on' {
        Test-Path (Join-Path $RepoRoot 'src/TestResultsAggregator.psm1') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $workflow = Join-Path $RepoRoot '.github/workflows/test-results-aggregator.yml'
        & actionlint $workflow 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
