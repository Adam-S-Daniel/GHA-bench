# Workflow.Tests.ps1
# Structural tests for the GitHub Actions workflow.
#   * Parse the YAML and assert on triggers, jobs, steps and dependencies.
#   * Verify the workflow references real script / fixture files.
#   * Verify actionlint passes (exit code 0).
#
# Run with: Invoke-Pester -Path ./Workflow.Tests.ps1

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/pr-label-assigner.yml'
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = ConvertFrom-Yaml (Get-Content -LiteralPath $WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML with a name' {
        $script:Wf.name | Should -Be 'PR Label Assigner'
    }
}

Describe 'Triggers' {
    # Note: PowerShell-yaml parses the YAML key `on` (a boolean-like token) to
    # the string key 'on'. We access it explicitly.
    It 'declares push, pull_request and workflow_dispatch triggers' {
        $on = $script:Wf['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }
}

Describe 'Permissions' {
    It 'sets contents: read at the top level (least privilege)' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }
}

Describe 'Jobs' {
    It 'defines a test job and a label job' {
        $script:Wf.jobs.Keys | Should -Contain 'test'
        $script:Wf.jobs.Keys | Should -Contain 'label'
    }

    It 'makes the label job depend on the test job' {
        $script:Wf.jobs.label.needs | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Wf.jobs.test.'runs-on'  | Should -Be 'ubuntu-latest'
        $script:Wf.jobs.label.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in both jobs' {
        $script:Wf.jobs.test.steps.uses  | Should -Contain 'actions/checkout@v4'
        $script:Wf.jobs.label.steps.uses | Should -Contain 'actions/checkout@v4'
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($job in $script:Wf.jobs.Values) {
            foreach ($step in $job.steps) {
                if ($step.ContainsKey('run')) {
                    $step.shell | Should -Be 'pwsh'
                }
            }
        }
    }

    It 'invokes the assigner script in the label job' {
        $runSteps = $script:Wf.jobs.label.steps | Where-Object { $_.ContainsKey('run') }
        ($runSteps.run -join "`n") | Should -Match 'PrLabelAssigner\.ps1'
    }
}

Describe 'Referenced files exist' {
    It 'references the assigner script which is present' {
        Test-Path -LiteralPath (Join-Path $script:Root 'PrLabelAssigner.ps1') | Should -BeTrue
    }

    It 'references the Pester test file which is present' {
        Test-Path -LiteralPath (Join-Path $script:Root 'PrLabelAssigner.Tests.ps1') | Should -BeTrue
    }

    It 'references fixture files which are present' {
        Test-Path -LiteralPath (Join-Path $script:Root 'fixtures/config.json')        | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:Root 'fixtures/changed-files.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
