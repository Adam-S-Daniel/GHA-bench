#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Workflow structure tests.

    These assert that .github/workflows/secret-rotation-validator.yml is a
    well-formed GitHub Actions workflow that wires up our scripts correctly, and
    that it passes actionlint. They live OUTSIDE ./tests on purpose: they depend on
    host tooling (actionlint, powershell-yaml) that is not present inside the act
    runner container, so we never want the workflow's own in-container test job to
    try to run them. Run them locally with:  Invoke-Pester -Path ./meta-tests
#>

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github' 'workflows' 'secret-rotation-validator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = Get-Content -Raw -LiteralPath $script:WorkflowPath | ConvertFrom-Yaml
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output was:`n$($output -join "`n")"
    }

    It 'is valid YAML that parses to a mapping' {
        $script:Wf | Should -BeOfType [System.Collections.IDictionary]
    }
}

Describe 'Triggers' {
    It 'defines the expected trigger events' {
        # YAML 1.1 would turn "on" into boolean true; powershell-yaml keeps it as "on".
        $on = $script:Wf['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'has a cron schedule' {
        $script:Wf['on'].schedule[0].cron | Should -Not -BeNullOrEmpty
    }

    It 'exposes workflow_dispatch inputs for warning window and config' {
        $inputs = $script:Wf['on'].workflow_dispatch.inputs
        $inputs.Keys | Should -Contain 'warning_days'
        $inputs.Keys | Should -Contain 'config_path'
        $inputs.Keys | Should -Contain 'fail_on_expired'
    }
}

Describe 'Permissions' {
    It 'requests least-privilege read-only contents access' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }
}

Describe 'Jobs' {
    It 'defines a test job and a validate job' {
        $script:Wf.jobs.Keys | Should -Contain 'test'
        $script:Wf.jobs.Keys | Should -Contain 'validate'
    }

    It 'makes validate depend on test (job dependency)' {
        @($script:Wf.jobs.validate.needs) | Should -Contain 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Wf.jobs.test.'runs-on'     | Should -Be 'ubuntu-latest'
        $script:Wf.jobs.validate.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in 'test', 'validate') {
            $uses = $script:Wf.jobs.$jobName.steps.uses
            $uses | Should -Contain 'actions/checkout@v4' -Because "job '$jobName' must check out the code"
        }
    }

    It 'runs the Pester suite in the test job via shell: pwsh' {
        $pesterStep = $script:Wf.jobs.test.steps | Where-Object { $_.run -match 'Invoke-Pester' }
        $pesterStep              | Should -Not -BeNullOrEmpty
        $pesterStep.shell        | Should -Be 'pwsh'
    }

    It 'invokes the validator script via shell: pwsh in the validate job' {
        $runSteps = $script:Wf.jobs.validate.steps | Where-Object { $_.run -match 'Invoke-SecretRotationValidator\.ps1' }
        @($runSteps).Count       | Should -BeGreaterThan 0
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
    }

    It 'produces both markdown and json reports' {
        $runText = ($script:Wf.jobs.validate.steps.run -join "`n")
        $runText | Should -Match '-Format markdown'
        $runText | Should -Match '-Format json'
    }
}

Describe 'Script references resolve to real files' {
    It 'references the validator entry script which exists on disk' {
        $runText = ($script:Wf.jobs.validate.steps.run -join "`n")
        $runText | Should -Match 'Invoke-SecretRotationValidator\.ps1'
        Test-Path (Join-Path $script:Root 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
    }

    It 'has the module the entry script imports' {
        Test-Path (Join-Path $script:Root 'src' 'SecretRotation.psm1') | Should -BeTrue
    }

    It 'has the Pester test directory the workflow runs' {
        Test-Path (Join-Path $script:Root 'tests') | Should -BeTrue
    }

    It 'has the default secrets config the workflow reads' {
        # default SECRETS_CONFIG fallback in the workflow
        Test-Path (Join-Path $script:Root 'fixtures' 'secrets.json') | Should -BeTrue
    }
}
