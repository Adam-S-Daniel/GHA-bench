#requires -Modules Pester

# Structure tests for the GitHub Actions workflow. These parse the YAML, assert
# the expected triggers/jobs/steps, confirm every referenced script file exists,
# and confirm the workflow passes actionlint. They run locally (not in act).

BeforeAll {
    $script:Root = $PSScriptRoot
    $script:WorkflowPath = Join-Path $Root '.github/workflows/environment-matrix-generator.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml (Get-Content -LiteralPath $WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML that parses to a hashtable' {
        $script:Workflow | Should -BeOfType [System.Collections.IDictionary]
    }
}

Describe 'Workflow triggers' {
    BeforeAll { $script:On = $script:Workflow['on'] }

    It 'triggers on push, pull_request, schedule, and workflow_dispatch' {
        $script:On.Keys | Should -Contain 'push'
        $script:On.Keys | Should -Contain 'pull_request'
        $script:On.Keys | Should -Contain 'schedule'
        $script:On.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'defines a valid weekly schedule' {
        $script:On.schedule[0].cron | Should -Be '0 6 * * 1'
    }

    It 'exposes a config_path workflow_dispatch input with a sensible default' {
        $script:On.workflow_dispatch.inputs.config_path.default | Should -Be 'matrix-config.json'
    }
}

Describe 'Workflow permissions and env' {
    It 'requests least-privilege read-only contents permission' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'sets a default MATRIX_CONFIG_PATH environment variable' {
        $script:Workflow.env.MATRIX_CONFIG_PATH | Should -Be 'matrix-config.json'
    }
}

Describe 'Workflow jobs' {
    BeforeAll { $script:Jobs = $script:Workflow.jobs }

    It 'defines generate, build, and summary jobs' {
        $script:Jobs.Keys | Should -Contain 'generate'
        $script:Jobs.Keys | Should -Contain 'build'
        $script:Jobs.Keys | Should -Contain 'summary'
    }

    It 'wires up job dependencies (build needs generate; summary needs both)' {
        $script:Jobs.build.needs | Should -Be 'generate'
        $script:Jobs.summary.needs | Should -Contain 'generate'
        $script:Jobs.summary.needs | Should -Contain 'build'
    }

    It 'checks out the repository with actions/checkout@v4' {
        $steps = $script:Jobs.generate.steps
        @($steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }).Count | Should -Be 1
    }

    It 'runs the Pester unit tests in the generate job' {
        $runSteps = $script:Jobs.generate.steps | Where-Object { $_.run }
        ($runSteps.run -join "`n") | Should -Match 'Invoke-Pester'
    }

    It 'invokes Generate-Matrix.ps1 in the generate job' {
        $runSteps = $script:Jobs.generate.steps | Where-Object { $_.run }
        ($runSteps.run -join "`n") | Should -Match 'Generate-Matrix\.ps1'
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($jobName in $script:Jobs.Keys) {
            foreach ($step in $script:Jobs[$jobName].steps) {
                if ($step.run) { $step.shell | Should -Be 'pwsh' }
            }
        }
    }

    It 'consumes the generated matrix via fromJson in the build job' {
        $script:Jobs.build.strategy.matrix | Should -Match 'fromJson\(needs\.generate\.outputs\.matrix\)'
    }
}

Describe 'Referenced files exist' {
    It 'references scripts that are present on disk' {
        Test-Path (Join-Path $script:Root 'MatrixGenerator.psm1')      | Should -BeTrue
        Test-Path (Join-Path $script:Root 'Generate-Matrix.ps1')       | Should -BeTrue
        Test-Path (Join-Path $script:Root 'MatrixGenerator.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'matrix-config.json')        | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed' ; return }
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}
