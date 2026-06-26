# Workflow structure tests: validate the GitHub Actions workflow's YAML
# structure, that it references real script paths, and that actionlint passes.
# These run locally (not inside act) and complement the act harness.

BeforeAll {
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/test-results-aggregator.yml'
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Yaml = ConvertFrom-Yaml (Get-Content $script:WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path $script:WorkflowPath | Should -Be $true
    }

    It 'is valid parseable YAML with a name' {
        $script:Yaml.name | Should -Be 'Test Results Aggregator'
    }
}

Describe 'Workflow triggers' {
    # In YAML, the "on:" key is parsed by some loaders as the boolean true.
    BeforeAll {
        $script:On = if ($script:Yaml.ContainsKey('on')) { $script:Yaml['on'] } else { $script:Yaml[$true] }
    }

    It 'triggers on push, pull_request, schedule and workflow_dispatch' {
        $script:On.Keys | Should -Contain 'push'
        $script:On.Keys | Should -Contain 'pull_request'
        $script:On.Keys | Should -Contain 'schedule'
        $script:On.Keys | Should -Contain 'workflow_dispatch'
    }
}

Describe 'Workflow permissions and jobs' {
    It 'declares least-privilege contents:read permission' {
        $script:Yaml.permissions.contents | Should -Be 'read'
    }

    It 'defines unit-tests and aggregate jobs' {
        $script:Yaml.jobs.Keys | Should -Contain 'unit-tests'
        $script:Yaml.jobs.Keys | Should -Contain 'aggregate'
    }

    It 'makes aggregate depend on unit-tests' {
        $script:Yaml.jobs.aggregate.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repo with actions/checkout@v4 in both jobs' {
        foreach ($job in 'unit-tests', 'aggregate') {
            $uses = $script:Yaml.jobs[$job].steps.uses
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for run steps (not pwsh -Command from bash)' {
        $runSteps = @()
        foreach ($job in $script:Yaml.jobs.Keys) {
            $runSteps += $script:Yaml.jobs[$job].steps | Where-Object { $_.run }
        }
        $runSteps | Should -Not -BeNullOrEmpty
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
    }
}

Describe 'Workflow references real files' {
    It 'references the aggregator script that exists on disk' {
        $aggStep = $script:Yaml.jobs.aggregate.steps | Where-Object { $_.run -match 'TestResultsAggregator\.ps1' }
        $aggStep | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $PSScriptRoot 'TestResultsAggregator.ps1') | Should -Be $true
    }

    It 'references the Pester test file that exists on disk' {
        $testStep = $script:Yaml.jobs.'unit-tests'.steps | Where-Object { $_.run -match 'TestResultsAggregator\.Tests\.ps1' }
        $testStep | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $PSScriptRoot 'TestResultsAggregator.Tests.ps1') | Should -Be $true
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
