#requires -Modules Pester
#
# WorkflowStructure.Tests.ps1
#
# Static structural validation of the GitHub Actions workflow. These tests do
# NOT run act (they are fast and deterministic): they parse the workflow YAML,
# assert on its triggers/jobs/steps, verify it references real script files,
# and confirm actionlint passes cleanly.
#

BeforeAll {
    Import-Module powershell-yaml -Force
    $script:root         = $PSScriptRoot
    $script:workflowPath = Join-Path $script:root '.github/workflows/secret-rotation-validator.yml'
    $script:wf           = ConvertFrom-Yaml (Get-Content $script:workflowPath -Raw)
}

Describe 'Workflow file exists and parses' {
    It 'has a workflow file at the expected path' {
        Test-Path $script:workflowPath | Should -BeTrue
    }
    It 'parses as valid YAML into a workflow object' {
        $script:wf | Should -Not -BeNullOrEmpty
        $script:wf.name | Should -Be 'Secret Rotation Validator'
    }
}

Describe 'Triggers' {
    BeforeAll { $script:on = $script:wf['on'] }

    It 'declares push, pull_request, schedule and workflow_dispatch triggers' {
        $script:on.Keys | Should -Contain 'push'
        $script:on.Keys | Should -Contain 'pull_request'
        $script:on.Keys | Should -Contain 'schedule'
        $script:on.Keys | Should -Contain 'workflow_dispatch'
    }
    It 'defines a cron schedule' {
        $script:on.schedule[0].cron | Should -Be '0 7 * * *'
    }
    It 'exposes workflow_dispatch inputs for warning_days and output_format' {
        $script:on.workflow_dispatch.inputs.Keys | Should -Contain 'warning_days'
        $script:on.workflow_dispatch.inputs.Keys | Should -Contain 'output_format'
    }
}

Describe 'Permissions and environment' {
    It 'sets least-privilege contents: read permission' {
        $script:wf.permissions.contents | Should -Be 'read'
    }
    It 'pins a deterministic REFERENCE_DATE and default config' {
        $script:wf.env.REFERENCE_DATE | Should -Be '2026-06-27'
        $script:wf.env.SECRETS_CONFIG | Should -Be 'fixtures/secrets.json'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines unit-tests and validate jobs' {
        $script:wf.jobs.Keys | Should -Contain 'unit-tests'
        $script:wf.jobs.Keys | Should -Contain 'validate'
    }
    It 'makes validate depend on unit-tests' {
        $script:wf.jobs.validate.needs | Should -Be 'unit-tests'
    }
    It 'runs both jobs on ubuntu-latest' {
        $script:wf.jobs.'unit-tests'.'runs-on' | Should -Be 'ubuntu-latest'
        $script:wf.jobs.validate.'runs-on'     | Should -Be 'ubuntu-latest'
    }
}

Describe 'Steps reference real files and use pwsh' {
    It 'checks out the repo with actions/checkout@v4 in both jobs' {
        $unitUses = $script:wf.jobs.'unit-tests'.steps | ForEach-Object { $_.uses } | Where-Object { $_ }
        $valUses  = $script:wf.jobs.validate.steps    | ForEach-Object { $_.uses } | Where-Object { $_ }
        $unitUses | Should -Contain 'actions/checkout@v4'
        $valUses  | Should -Contain 'actions/checkout@v4'
    }
    It 'uses shell: pwsh for every run step (no pwsh -Command/-File from bash)' {
        $runSteps = @($script:wf.jobs.'unit-tests'.steps + $script:wf.jobs.validate.steps) |
            Where-Object { $_.ContainsKey('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
    }
    It 'references Invoke-Validator.ps1, which exists on disk' {
        $allRun = (@($script:wf.jobs.'unit-tests'.steps + $script:wf.jobs.validate.steps) |
            Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $allRun | Should -Match 'Invoke-Validator\.ps1'
        Test-Path (Join-Path $script:root 'Invoke-Validator.ps1') | Should -BeTrue
    }
    It 'references the Pester test file, which exists on disk' {
        $allRun = (@($script:wf.jobs.'unit-tests'.steps) |
            Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $allRun | Should -Match 'SecretRotationValidator\.Tests\.ps1'
        Test-Path (Join-Path $script:root 'SecretRotationValidator.Tests.ps1') | Should -BeTrue
    }
    It 'has the module and default fixture on disk' {
        Test-Path (Join-Path $script:root 'SecretRotationValidator.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:root 'fixtures/secrets.json')        | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
