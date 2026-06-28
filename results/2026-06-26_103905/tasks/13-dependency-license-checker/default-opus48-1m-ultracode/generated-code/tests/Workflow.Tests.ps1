<#
    Workflow STRUCTURE tests (static, host-side).

    These verify the GitHub Actions workflow itself: that it parses, declares the
    expected triggers/jobs/steps, references real script files, and passes
    actionlint. They do not invoke act (that is run-act-tests.ps1's job).
#>

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github' 'workflows' 'dependency-license-checker.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists and parses as YAML' {
        Test-Path $script:WorkflowPath | Should -BeTrue
        $script:Wf | Should -Not -BeNullOrEmpty
    }

    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Triggers' {
    It 'declares push, pull_request, workflow_dispatch and schedule' {
        $on = $script:Wf['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'uses a valid weekly cron schedule' {
        $cron = $script:Wf['on'].schedule[0].cron
        $cron | Should -Be '0 6 * * 1'
    }
}

Describe 'Permissions and environment' {
    It 'grants least-privilege contents: read' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }

    It 'defines the policy and license-database env vars' {
        $script:Wf.env.POLICY_FILE     | Should -Be 'config/policy.json'
        $script:Wf.env.LICENSE_DB_FILE | Should -Be 'config/licenses.json'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines the unit-tests, license-check and gate jobs' {
        $script:Wf.jobs.Keys | Should -Contain 'unit-tests'
        $script:Wf.jobs.Keys | Should -Contain 'license-check'
        $script:Wf.jobs.Keys | Should -Contain 'gate'
    }

    It 'wires the job dependency graph unit-tests -> license-check -> gate' {
        $script:Wf.jobs['license-check'].needs | Should -Be 'unit-tests'
        $script:Wf.jobs['gate'].needs          | Should -Be 'license-check'
    }

    It 'runs every job on ubuntu-latest' {
        foreach ($jobName in $script:Wf.jobs.Keys) {
            $script:Wf.jobs[$jobName]['runs-on'] | Should -Be 'ubuntu-latest'
        }
    }
}

Describe 'Steps reference real files' {
    It 'checks out the repo with actions/checkout@v4' {
        $uses = $script:Wf.jobs['unit-tests'].steps | ForEach-Object { $_.uses } | Where-Object { $_ }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'invokes the Pester runner, which exists on disk' {
        $run = ($script:Wf.jobs['unit-tests'].steps | Where-Object { $_.run }).run -join "`n"
        $run | Should -BeLike '*tests/Invoke-PesterTests.ps1*'
        Test-Path (Join-Path $script:Root 'tests' 'Invoke-PesterTests.ps1') | Should -BeTrue
    }

    It 'invokes the fixture-check runner, which exists on disk' {
        $run = ($script:Wf.jobs['license-check'].steps | Where-Object { $_.run }).run -join "`n"
        $run | Should -BeLike '*tests/Run-FixtureChecks.ps1*'
        Test-Path (Join-Path $script:Root 'tests' 'Run-FixtureChecks.ps1') | Should -BeTrue
    }

    It 'uses shell: pwsh for every run step (PowerShell mode requirement)' {
        foreach ($jobName in $script:Wf.jobs.Keys) {
            foreach ($step in $script:Wf.jobs[$jobName].steps) {
                if ($step.run) { $step.shell | Should -Be 'pwsh' }
            }
        }
    }
}

Describe 'Referenced project files exist' {
    It 'has the module, CLI and config the runners depend on' {
        Test-Path (Join-Path $script:Root 'src' 'DependencyLicenseChecker.psm1') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'bin' 'check-licenses.ps1')            | Should -BeTrue
        Test-Path (Join-Path $script:Root 'config' 'policy.json')                | Should -BeTrue
        Test-Path (Join-Path $script:Root 'config' 'licenses.json')              | Should -BeTrue
        (Get-ChildItem (Join-Path $script:Root 'tests' 'fixtures' 'manifests')).Count | Should -BeGreaterThan 0
    }
}
