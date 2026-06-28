# Structure / static-validation tests for the GitHub Actions workflow.
#
# These are fast and do NOT invoke act. They parse the workflow YAML and assert
# its shape, verify the referenced script files exist on disk, and confirm that
# actionlint validates the file cleanly.
#
# Run with:  Invoke-Pester -Path tests/Workflow.Structure.Tests.ps1

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/test-results-aggregator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow YAML structure' {

    It 'exists and parses as valid YAML' {
        Test-Path $script:WorkflowPath | Should -BeTrue
        $script:Workflow | Should -Not -BeNullOrEmpty
    }

    It 'has a human-readable name' {
        $script:Workflow['name'] | Should -Be 'Test Results Aggregator'
    }

    It 'declares the expected trigger events' {
        # NOTE: the YAML key "on" is parsed by some loaders as the boolean true,
        # so look it up tolerantly.
        $on = $script:Workflow['on']
        if ($null -eq $on) { $on = $script:Workflow[$true] }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'requests least-privilege contents:read permissions' {
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines a RESULTS_DIR environment variable' {
        $script:Workflow['env'].Keys | Should -Contain 'RESULTS_DIR'
    }

    It 'defines an aggregate job running on ubuntu-latest' {
        $job = $script:Workflow['jobs']['aggregate']
        $job | Should -Not -BeNullOrEmpty
        $job['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4' {
        $steps = $script:Workflow['jobs']['aggregate']['steps']
        ($steps.uses) | Should -Contain 'actions/checkout@v4'
    }

    It 'uses pwsh shell for every run step (no bash -> pwsh invocation)' {
        $steps = $script:Workflow['jobs']['aggregate']['steps']
        $runSteps = $steps | Where-Object { $_.ContainsKey('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) {
            $s['shell'] | Should -Be 'pwsh'
        }
    }

    It 'invokes the aggregator script and the Pester suite' {
        $raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $raw | Should -Match 'Invoke-Aggregator\.ps1'
        $raw | Should -Match 'Invoke-Pester'
    }
}

Describe 'Workflow references real files' {

    It 'references the aggregator entry script, which exists' {
        Test-Path (Join-Path $script:Root 'Invoke-Aggregator.ps1') | Should -BeTrue
    }

    It 'references the module and unit test files, which exist' {
        Test-Path (Join-Path $script:Root 'src/TestResultsAggregator.psm1')   | Should -BeTrue
        Test-Path (Join-Path $script:Root 'tests/TestResultsAggregator.Tests.ps1') | Should -BeTrue
    }

    It 'ships a default test-results directory to aggregate' {
        (Get-ChildItem (Join-Path $script:Root 'test-results') -File).Count | Should -BeGreaterThan 0
    }
}

Describe 'actionlint validation' {

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { Write-Host ($output | Out-String) }
        $code | Should -Be 0
    }
}
