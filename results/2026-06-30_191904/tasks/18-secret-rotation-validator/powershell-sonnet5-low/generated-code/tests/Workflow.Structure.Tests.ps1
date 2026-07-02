<#
    Structural tests for the GitHub Actions workflow: parses the YAML and
    checks triggers/jobs/steps, verifies referenced script files exist, and
    verifies actionlint passes cleanly.
#>

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:workflowPath = Join-Path $repoRoot '.github/workflows/secret-rotation-validator.yml'
    $script:workflow = ConvertFrom-Yaml (Get-Content -Path $workflowPath -Raw)
}

Describe 'secret-rotation-validator.yml structure' {

    It 'exists' {
        Test-Path $script:workflowPath | Should -BeTrue
    }

    It 'defines push, pull_request, workflow_dispatch, and schedule triggers' {
        # YAML key 'on' is parsed as boolean key True in some parsers; handle both.
        $onSection = if ($script:workflow.ContainsKey('on')) { $script:workflow['on'] } else { $script:workflow['True'] }

        $onSection.Keys | Should -Contain 'push'
        $onSection.Keys | Should -Contain 'pull_request'
        $onSection.Keys | Should -Contain 'workflow_dispatch'
        $onSection.Keys | Should -Contain 'schedule'
    }

    It 'defines a test job and a validate-rotation job that depends on it' {
        $script:workflow.jobs.Keys | Should -Contain 'test'
        $script:workflow.jobs.Keys | Should -Contain 'validate-rotation'
        $script:workflow.jobs['validate-rotation'].needs | Should -Be 'test'
    }

    It 'declares read-only top-level permissions' {
        $script:workflow.permissions.contents | Should -Be 'read'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($jobName in @('test', 'validate-rotation')) {
            $steps = $script:workflow.jobs[$jobName].steps
            $checkoutStep = $steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }
            $checkoutStep | Should -Not -BeNullOrEmpty
        }
    }

    It 'runs steps with shell: pwsh' {
        foreach ($jobName in @('test', 'validate-rotation')) {
            $steps = $script:workflow.jobs[$jobName].steps | Where-Object { $_.run }
            foreach ($step in $steps) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'references script and fixture files that actually exist in the repo' {
        Test-Path (Join-Path $script:repoRoot 'tests') | Should -BeTrue
        Test-Path (Join-Path $script:repoRoot 'Invoke-SecretRotationCheck.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:repoRoot 'fixtures/secrets.sample.json') | Should -BeTrue
        Test-Path (Join-Path $script:repoRoot 'fixtures/secrets.allok.json') | Should -BeTrue
    }

    It 'passes actionlint validation' {
        $actionlintOutput = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($actionlintOutput -join "`n")
    }
}
