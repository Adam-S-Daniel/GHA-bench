<#
.SYNOPSIS
    Structure tests for the GitHub Actions workflow.

.DESCRIPTION
    Parses the workflow YAML and asserts on its structure (triggers,
    jobs, steps, dependencies), verifies every path the workflow
    references actually exists, and asserts actionlint passes.
#>

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'test-results-aggregator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Yaml = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml

    # YAML 1.1 parsers may resolve the bare 'on' key to boolean $true.
    $script:Triggers = if ($Yaml.Contains('on')) { $Yaml['on'] } else { $Yaml[$true] }
}

Describe 'Workflow structure' {

    It 'exists and is valid YAML' {
        Test-Path $WorkflowPath | Should -BeTrue
        $Yaml | Should -Not -BeNullOrEmpty
    }

    It 'triggers on push, pull_request and workflow_dispatch' {
        $Triggers.Keys | Should -Contain 'push'
        $Triggers.Keys | Should -Contain 'pull_request'
        $Triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'restricts permissions to contents: read' {
        $Yaml.permissions.contents | Should -Be 'read'
    }

    It 'defines the unit-tests and aggregate jobs' {
        $Yaml.jobs.Keys | Should -Contain 'unit-tests'
        $Yaml.jobs.Keys | Should -Contain 'aggregate'
    }

    It 'makes the aggregate job depend on unit-tests' {
        $Yaml.jobs.aggregate.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($job in $Yaml.jobs.Values) {
            $job.steps[0].uses | Should -Be 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($job in $Yaml.jobs.Values) {
            foreach ($step in ($job.steps | Where-Object { $_.Contains('run') })) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'invokes the aggregator entry script' {
        $runStep = $Yaml.jobs.aggregate.steps | Where-Object { $_.Contains('run') } | Select-Object -First 1
        $runStep.run | Should -Match 'Invoke-TestResultsAggregator\.ps1'
    }
}

Describe 'Workflow file references' {

    It 'references files and directories that exist in the repo' {
        # Everything the workflow needs at runtime must be committed.
        Join-Path $RepoRoot 'Invoke-TestResultsAggregator.ps1' | Should -Exist
        Join-Path $RepoRoot 'TestResultsAggregator.psm1'       | Should -Exist
        Join-Path $RepoRoot 'tests' 'unit'                     | Should -Exist
    }

    It 'points FIXTURES_DIR at an existing directory containing result files' {
        $fixturesDir = Join-Path $RepoRoot $Yaml.env.FIXTURES_DIR
        $fixturesDir | Should -Exist
        @(Get-ChildItem $fixturesDir -Include *.xml, *.json -Recurse).Count |
            Should -BeGreaterThan 0
    }
}

Describe 'actionlint validation' {

    It 'passes actionlint with exit code 0' {
        $null = Get-Command actionlint -ErrorAction Stop
        $output = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint reported: $($output -join "`n")"
    }
}
