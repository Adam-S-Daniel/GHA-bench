# Structure and lint tests for the GitHub Actions workflow.
# Run with: Invoke-Pester ./Tests/Workflow.Tests.ps1

BeforeAll {
    $script:RepoRoot = "$PSScriptRoot/.."
    $script:WorkflowPath = "$RepoRoot/.github/workflows/test-results-aggregator.yml"

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -Raw -LiteralPath $WorkflowPath | ConvertFrom-Yaml -Ordered
}

Describe 'Workflow file structure' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'defines push, pull_request, workflow_dispatch, and schedule triggers' {
        # YAML parses the bare "on" key as boolean $true, so look it up by key name.
        $onKey = $Workflow.Keys | Where-Object { $_ -eq 'on' -or $_ -eq $true }
        $triggers = $Workflow[$onKey]
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'declares read-only top-level permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines a unit-tests job and an aggregate job that depends on it' {
        $Workflow.jobs.Keys | Should -Contain 'unit-tests'
        $Workflow.jobs.Keys | Should -Contain 'aggregate'
        $Workflow.jobs.aggregate.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repository in both jobs using actions/checkout@v4' {
        foreach ($jobName in @('unit-tests', 'aggregate')) {
            $checkoutStep = $Workflow.jobs[$jobName].steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }
            $checkoutStep | Should -Not -BeNullOrEmpty -Because "job '$jobName' should check out the repo"
        }
    }

    It 'runs its script/test steps with shell: pwsh' {
        foreach ($jobName in @('unit-tests', 'aggregate')) {
            $runSteps = $Workflow.jobs[$jobName].steps | Where-Object { $_.run }
            foreach ($step in $runSteps) {
                $step.shell | Should -Be 'pwsh' -Because "step '$($step.name)' in job '$jobName' should use shell: pwsh"
            }
        }
    }
}

Describe 'Workflow references real project files' {
    It 'references the Pester unit test file, and that file exists' {
        $testStep = $Workflow.jobs.'unit-tests'.steps | Where-Object { $_.run -match 'TestResultsAggregator\.Tests\.ps1' }
        $testStep | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath "$RepoRoot/Tests/TestResultsAggregator.Tests.ps1" | Should -BeTrue
    }

    It 'references the aggregator script, and that file exists' {
        $aggregateStep = $Workflow.jobs.aggregate.steps | Where-Object { $_.run -match 'TestResultsAggregator\.ps1' }
        $aggregateStep | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath "$RepoRoot/TestResultsAggregator.ps1" | Should -BeTrue
    }

    It 'references a fixtures directory that exists and contains sample result files' {
        Test-Path -LiteralPath "$RepoRoot/fixtures/matrix" | Should -BeTrue
        (Get-ChildItem -LiteralPath "$RepoRoot/fixtures/matrix" -Include '*.xml', '*.json' -File).Count | Should -BeGreaterThan 0
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }

        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
