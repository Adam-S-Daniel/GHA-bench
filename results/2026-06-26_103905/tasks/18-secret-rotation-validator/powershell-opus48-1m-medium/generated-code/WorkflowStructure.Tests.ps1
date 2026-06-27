#requires -Modules Pester

# Structural tests for the GitHub Actions workflow. These parse the YAML and
# assert the workflow has the expected triggers, jobs and steps, references the
# script files that actually exist, and passes actionlint.

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/secret-rotation-validator.yml'
    $script:Workflow     = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML that parses to a mapping' {
        $script:Workflow | Should -BeOfType ([System.Collections.IDictionary])
    }
}

Describe 'Triggers' {
    BeforeAll { $script:On = $script:Workflow['on'] }

    It 'defines the expected trigger events' {
        $script:On.Keys | Should -Contain 'push'
        $script:On.Keys | Should -Contain 'pull_request'
        $script:On.Keys | Should -Contain 'schedule'
        $script:On.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'has a daily schedule cron' {
        $script:On.schedule[0].cron | Should -Be '0 8 * * *'
    }
}

Describe 'Permissions and environment' {
    It 'grants least-privilege read access to contents' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the shared configuration env vars' {
        $script:Workflow.env.CONFIG_PATH | Should -Be 'secrets.json'
        $script:Workflow.env.WARNING_DAYS | Should -Be '7'
        $script:Workflow.env.REFERENCE_DATE | Should -Be '2026-06-26'
    }
}

Describe 'Jobs' {
    It 'defines the test and report jobs' {
        $script:Workflow.jobs.Keys | Should -Contain 'test'
        $script:Workflow.jobs.Keys | Should -Contain 'report'
    }

    It 'wires up a job dependency: report needs test' {
        $script:Workflow.jobs.report.needs | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Workflow.jobs.test.'runs-on'   | Should -Be 'ubuntu-latest'
        $script:Workflow.jobs.report.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repository in every job' {
        $checkouts = @($script:Workflow.jobs.test.steps; $script:Workflow.jobs.report.steps) |
            Where-Object { $_.uses -eq 'actions/checkout@v4' }
        $checkouts.Count | Should -Be 2
    }

    It 'uses pwsh as the shell for run steps' {
        $runSteps = @($script:Workflow.jobs.test.steps; $script:Workflow.jobs.report.steps) |
            Where-Object { $_.ContainsKey('run') }
        $runSteps | ForEach-Object { $_.shell | Should -Be 'pwsh' }
    }
}

Describe 'Script references' {
    It 'references the implementation script, which exists' {
        $allRun = (@($script:Workflow.jobs.test.steps; $script:Workflow.jobs.report.steps) |
            Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $allRun | Should -Match 'SecretRotationValidator\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'SecretRotationValidator.ps1') | Should -BeTrue
    }

    It 'references the unit test file, which exists' {
        $testRun = ($script:Workflow.jobs.test.steps | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $testRun | Should -Match 'SecretRotationValidator\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'SecretRotationValidator.Tests.ps1') | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes actionlint with no errors' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output: $output"
    }
}
