#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Structure / static-validation tests for the GitHub Actions workflow.
# These run locally (they validate the workflow itself and so cannot run
# *inside* act). The end-to-end execution-through-act lives in Run-ActHarness.ps1.

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/pr-label-assigner.yml'

    Import-Module powershell-yaml -ErrorAction SilentlyContinue
    $script:Wf = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)

    # Collect every 'run:' script body and every 'uses:' reference across all jobs.
    $script:AllRun = [System.Collections.Generic.List[string]]::new()
    $script:AllUses = [System.Collections.Generic.List[string]]::new()
    foreach ($job in $script:Wf['jobs'].Values) {
        foreach ($step in $job['steps']) {
            if ($step.ContainsKey('run'))  { $script:AllRun.Add([string]$step['run']) }
            if ($step.ContainsKey('uses')) { $script:AllUses.Add([string]$step['uses']) }
        }
    }
}

Describe 'Workflow file is present and valid' {
    It 'exists on disk' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }
    It 'parses as a YAML mapping' {
        $script:Wf | Should -BeOfType [hashtable]
    }
    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
    }
}

Describe 'Workflow triggers' {
    It 'has the expected name' {
        $script:Wf['name'] | Should -Be 'PR Label Assigner'
    }
    It 'triggers on push' {
        $script:Wf['on'].Keys | Should -Contain 'push'
    }
    It 'triggers on pull_request' {
        $script:Wf['on'].Keys | Should -Contain 'pull_request'
    }
    It 'supports manual workflow_dispatch' {
        $script:Wf['on'].Keys | Should -Contain 'workflow_dispatch'
    }
    It 'has a scheduled trigger' {
        $script:Wf['on'].Keys | Should -Contain 'schedule'
    }
}

Describe 'Workflow permissions and env' {
    It 'declares least-privilege permissions' {
        $script:Wf['permissions']['contents'] | Should -Be 'read'
        $script:Wf['permissions']['pull-requests'] | Should -Be 'write'
    }
    It 'defines RULES_PATH and CHANGED_FILES env vars' {
        $script:Wf['env']['RULES_PATH'] | Should -Be 'fixtures/label-rules.json'
        $script:Wf['env']['CHANGED_FILES'] | Should -Be 'fixtures/changed-files.txt'
    }
}

Describe 'Workflow jobs and dependencies' {
    It 'defines a test job and an assign-labels job' {
        $script:Wf['jobs'].Keys | Should -Contain 'test'
        $script:Wf['jobs'].Keys | Should -Contain 'assign-labels'
    }
    It 'makes assign-labels depend on test (job dependency)' {
        $script:Wf['jobs']['assign-labels']['needs'] | Should -Be 'test'
    }
    It 'runs jobs on ubuntu-latest' {
        $script:Wf['jobs']['test']['runs-on'] | Should -Be 'ubuntu-latest'
        $script:Wf['jobs']['assign-labels']['runs-on'] | Should -Be 'ubuntu-latest'
    }
}

Describe 'Workflow steps reference real files' {
    It 'checks out the repo with actions/checkout@v4' {
        $script:AllUses | Should -Contain 'actions/checkout@v4'
    }
    It 'uses shell: pwsh for every run step' {
        foreach ($job in $script:Wf['jobs'].Values) {
            foreach ($step in $job['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh'
                }
            }
        }
    }
    It 'invokes the CLI entry script, which exists' {
        ($script:AllRun -join "`n") | Should -Match 'Invoke-PrLabelAssigner\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'Invoke-PrLabelAssigner.ps1') | Should -BeTrue
    }
    It 'runs the Pester unit-test file, which exists' {
        ($script:AllRun -join "`n") | Should -Match 'tests/PrLabelAssigner\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'tests/PrLabelAssigner.Tests.ps1') | Should -BeTrue
    }
    It 'references a rules config and module that exist on disk' {
        Test-Path -LiteralPath (Join-Path $script:Root 'fixtures/label-rules.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Root 'src/PrLabelAssigner.psm1') | Should -BeTrue
    }
}
