<#
    Workflow.Structure.Tests.ps1

    Static validation of the GitHub Actions workflow file: this does NOT execute
    the workflow (see Pipeline.Act.Tests.ps1 for that). It only checks the YAML
    structure, that referenced script paths exist on disk, and that actionlint
    reports a clean pass. These are "free" checks (no Docker/act needed) so they
    run first and fast.
#>

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $ProjectRoot '.github/workflows/test-results-aggregator.yml'
}

Describe 'Test Results Aggregator - Workflow file structure' {

    It 'exists at .github/workflows/test-results-aggregator.yml' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    Context 'YAML content' {
        BeforeAll {
            $script:WorkflowYaml = Get-Content -Path $script:WorkflowPath -Raw
            $script:Workflow = ConvertFrom-Yaml -Yaml $script:WorkflowYaml -Ordered
        }

        It 'parses as valid YAML' {
            $script:Workflow | Should -Not -BeNullOrEmpty
        }

        It 'declares push, pull_request and workflow_dispatch triggers' {
            # YAML key "on" is parsed by powershell-yaml as boolean key "True" in some
            # versions of the YAML 1.1 spec; guard for both forms.
            $onKey = if ($script:Workflow.Contains('on')) { 'on' } elseif ($script:Workflow.Contains('True')) { 'True' } else { $null }
            $onKey | Should -Not -BeNullOrEmpty
            $triggers = $script:Workflow[$onKey]
            $triggers.Contains('push') | Should -BeTrue
            $triggers.Contains('pull_request') | Should -BeTrue
            $triggers.Contains('workflow_dispatch') | Should -BeTrue
        }

        It 'declares read-only top-level permissions' {
            $script:Workflow['permissions'] | Should -Not -BeNullOrEmpty
            $script:Workflow['permissions']['contents'] | Should -Be 'read'
        }

        It 'declares a TEST_RESULTS_PATH environment variable' {
            $script:Workflow['env']['TEST_RESULTS_PATH'] | Should -Not -BeNullOrEmpty
        }

        It 'defines a collect job and an aggregate job' {
            $script:Workflow['jobs'].Contains('collect') | Should -BeTrue
            $script:Workflow['jobs'].Contains('aggregate') | Should -BeTrue
        }

        It 'has the aggregate job depend on the collect job via needs' {
            $script:Workflow['jobs']['aggregate']['needs'] | Should -Be 'collect'
        }

        It 'checks out the repository in both jobs' {
            foreach ($jobName in @('collect', 'aggregate')) {
                $steps = $script:Workflow['jobs'][$jobName]['steps']
                $usesActions = $steps | ForEach-Object { $_['uses'] } | Where-Object { $_ }
                $usesActions | Where-Object { $_ -like 'actions/checkout@v4' } | Should -Not -BeNullOrEmpty
            }
        }

        It 'runs the aggregate step with shell: pwsh' {
            $steps = $script:Workflow['jobs']['aggregate']['steps']
            $scriptStep = $steps | Where-Object { $_['run'] -and $_['run'] -match 'Aggregate-TestResults\.ps1' }
            $scriptStep | Should -Not -BeNullOrEmpty
            $scriptStep['shell'] | Should -Be 'pwsh'
        }
    }

    Context 'Referenced files exist' {
        BeforeAll {
            $script:WorkflowYaml = Get-Content -Path $script:WorkflowPath -Raw
        }

        It 'references the Aggregate-TestResults.ps1 entry script and the script exists' {
            $script:WorkflowYaml | Should -Match 'Aggregate-TestResults\.ps1'
            Join-Path $script:ProjectRoot 'Aggregate-TestResults.ps1' | Should -Exist
        }

        It 'the TestResultsAggregator module referenced by the entry script exists' {
            Join-Path $script:ProjectRoot 'TestResultsAggregator.psm1' | Should -Exist
        }

        It 'the default test-results fixture directory referenced by the workflow exists' {
            Join-Path $script:ProjectRoot 'test-results' | Should -Exist
        }
    }

    Context 'actionlint validation' {
        It 'passes actionlint with exit code 0 and no output' {
            $output = & actionlint $script:WorkflowPath 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                Write-Host "actionlint output:`n$output"
            }
            $exitCode | Should -Be 0
        }
    }
}
