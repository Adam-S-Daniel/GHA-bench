#
# Structural / static-analysis tests for the GitHub Actions workflow file.
# These run locally (not inside the act-executed pipeline) since they need
# the actionlint binary and want to validate the file before it is ever run.
#
BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'test-results-aggregator.yml'

    Import-Module powershell-yaml -ErrorAction Stop

    $script:WorkflowExists = Test-Path -LiteralPath $WorkflowPath
    if ($script:WorkflowExists) {
        $script:WorkflowYaml = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml -Ordered
    }
}

Describe 'Workflow file structure' {
    It 'Exists at .github/workflows/test-results-aggregator.yml' {
        $WorkflowExists | Should -BeTrue
    }

    It 'Is valid parseable YAML' {
        { Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml } | Should -Not -Throw
    }

    It 'Declares push, pull_request, workflow_dispatch, and schedule triggers' {
        # YAML parses the bare "on:" key as boolean $true in some parsers; powershell-yaml keeps it as 'on'.
        $onKey = if ($WorkflowYaml.Contains('on')) { 'on' } elseif ($WorkflowYaml.Contains($true)) { $true } else { $null }
        $onKey | Should -Not -BeNullOrEmpty

        $triggers = $WorkflowYaml[$onKey]
        $triggers.Contains('push') | Should -BeTrue
        $triggers.Contains('pull_request') | Should -BeTrue
        $triggers.Contains('workflow_dispatch') | Should -BeTrue
        $triggers.Contains('schedule') | Should -BeTrue
    }

    It 'Declares read-only contents permission' {
        $WorkflowYaml['permissions']['contents'] | Should -Be 'read'
    }

    It 'Defines a test job and an aggregate job, with aggregate depending on test' {
        $WorkflowYaml['jobs'].Contains('test') | Should -BeTrue
        $WorkflowYaml['jobs'].Contains('aggregate') | Should -BeTrue
        $WorkflowYaml['jobs']['aggregate']['needs'] | Should -Be 'test'
    }

    It 'Both jobs check out the repository as their first step' {
        foreach ($jobName in @('test', 'aggregate')) {
            $steps = $WorkflowYaml['jobs'][$jobName]['steps']
            $steps[0]['uses'] | Should -Match '^actions/checkout@v4'
        }
    }

    It 'Uses shell: pwsh for every run: step (per PowerShell-mode guidance)' {
        foreach ($jobName in @('test', 'aggregate')) {
            $runSteps = $WorkflowYaml['jobs'][$jobName]['steps'] | Where-Object { $_.Contains('run') }
            foreach ($step in $runSteps) {
                $step['shell'] | Should -Be 'pwsh'
            }
        }
    }

    It 'References Tests/TestResultsAggregator.Tests.ps1 and Tests/Aggregate-TestResults.Tests.ps1, and both files exist' {
        $testStep = $WorkflowYaml['jobs']['test']['steps'] | Where-Object { $_['name'] -eq 'Run unit tests' }
        $testStep['run'] | Should -Match 'Tests/TestResultsAggregator\.Tests\.ps1'
        $testStep['run'] | Should -Match 'Tests/Aggregate-TestResults\.Tests\.ps1'

        Test-Path (Join-Path $RepoRoot 'Tests' 'TestResultsAggregator.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'Tests' 'Aggregate-TestResults.Tests.ps1') | Should -BeTrue
    }

    It 'References Aggregate-TestResults.ps1 in the aggregate job, and the file exists' {
        $aggStep = $WorkflowYaml['jobs']['aggregate']['steps'] | Where-Object { $_.Contains('run') }
        ($aggStep['run'] -join "`n") | Should -Match '\./Aggregate-TestResults\.ps1'
        Test-Path (Join-Path $RepoRoot 'Aggregate-TestResults.ps1') | Should -BeTrue
    }

    It 'References a RESULTS_PATH that exists as a fixtures directory' {
        $resultsPath = $WorkflowYaml['jobs']['aggregate']['env']['RESULTS_PATH']
        $resultsPath | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $RepoRoot $resultsPath) -PathType Container | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'Passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }

        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
