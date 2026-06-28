#requires -Module Pester

# Structural tests for the GitHub Actions workflow. These verify that the
# committed workflow has the expected triggers / jobs / steps, that it points at
# files that actually exist, and that it passes `actionlint` cleanly.

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:Root         = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:Root '.github' 'workflows' 'environment-matrix-generator.yml'

    $script:Workflow = Get-Content -Path $script:WorkflowPath -Raw | ConvertFrom-Yaml

    # YAML 1.1 can fold the `on:` key into the boolean true; handle both.
    $script:OnSection = if ($script:Workflow.Contains('on')) {
        $script:Workflow['on']
    } else {
        $script:Workflow[$true]
    }
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML with a name' {
        $script:Workflow.name | Should -Not -BeNullOrEmpty
    }
}

Describe 'Triggers' {
    It 'fires on push, pull_request, workflow_dispatch and schedule' {
        $script:OnSection.Keys | Should -Contain 'push'
        $script:OnSection.Keys | Should -Contain 'pull_request'
        $script:OnSection.Keys | Should -Contain 'workflow_dispatch'
        $script:OnSection.Keys | Should -Contain 'schedule'
    }

    It 'has a valid weekly schedule cron' {
        $cron = $script:OnSection['schedule'][0]['cron']
        $cron | Should -Match '^\S+ \S+ \S+ \S+ \S+$'
    }

    It 'exposes a config_path dispatch input with a default' {
        $input = $script:OnSection['workflow_dispatch']['inputs']['config_path']
        $input | Should -Not -BeNullOrEmpty
        $input['default'] | Should -Be 'matrix-config.json'
    }
}

Describe 'Permissions and environment' {
    It 'declares least-privilege contents: read' {
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'sets the MATRIX_CONFIG_PATH environment variable' {
        $script:Workflow['env']['MATRIX_CONFIG_PATH'] | Should -Be 'matrix-config.json'
    }
}

Describe 'Jobs and dependencies' {
    It 'defines test, generate, build and report jobs' {
        $jobs = $script:Workflow['jobs'].Keys
        $jobs | Should -Contain 'test'
        $jobs | Should -Contain 'generate'
        $jobs | Should -Contain 'build'
        $jobs | Should -Contain 'report'
    }

    It 'wires the dependency chain test -> generate -> build -> report' {
        $script:Workflow['jobs']['generate']['needs'] | Should -Be 'test'
        $script:Workflow['jobs']['build']['needs']    | Should -Be 'generate'
        @($script:Workflow['jobs']['report']['needs']) | Should -Contain 'generate'
        @($script:Workflow['jobs']['report']['needs']) | Should -Contain 'build'
    }

    It 'exposes matrix and count outputs from the generate job' {
        $outputs = $script:Workflow['jobs']['generate']['outputs']
        $outputs.Keys | Should -Contain 'matrix'
        $outputs.Keys | Should -Contain 'count'
    }

    It 'builds via a dynamic matrix consumed with fromJSON' {
        $matrixExpr = $script:Workflow['jobs']['build']['strategy']['matrix']
        $matrixExpr | Should -Match 'fromJSON\(needs\.generate\.outputs\.matrix\)'
    }

    It 'sets fail-fast: false on the build fan-out' {
        $script:Workflow['jobs']['build']['strategy']['fail-fast'] | Should -Be $false
    }
}

Describe 'Steps reference real files and use pwsh' {
    It 'checks out the repo with actions/checkout@v4' {
        $uses = foreach ($jobName in $script:Workflow['jobs'].Keys) {
            foreach ($step in $script:Workflow['jobs'][$jobName]['steps']) {
                if ($step.Contains('uses')) { $step['uses'] }
            }
        }
        $uses | Should -Contain 'actions/checkout@v4'
    }

    It 'invokes Generate-Matrix.ps1 in the generate job' {
        $runScripts = foreach ($step in $script:Workflow['jobs']['generate']['steps']) {
            if ($step.Contains('run')) { $step['run'] }
        }
        ($runScripts -join "`n") | Should -Match 'Generate-Matrix\.ps1'
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($jobName in $script:Workflow['jobs'].Keys) {
            foreach ($step in $script:Workflow['jobs'][$jobName]['steps']) {
                if ($step.Contains('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "step '$($step['name'])' in job '$jobName' runs a script"
                }
            }
        }
    }
}

Describe 'Referenced project files exist' {
    It 'has the CLI script' {
        Test-Path (Join-Path $script:Root 'Generate-Matrix.ps1') | Should -BeTrue
    }
    It 'has the generator module' {
        Test-Path (Join-Path $script:Root 'src' 'MatrixGenerator.psm1') | Should -BeTrue
    }
    It 'has the unit test files referenced by the workflow' {
        Test-Path (Join-Path $script:Root 'tests' 'MatrixGenerator.Tests.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'tests' 'Generate-Matrix.Tests.ps1') | Should -BeTrue
    }
    It 'has the default matrix-config.json' {
        Test-Path (Join-Path $script:Root 'matrix-config.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint output:`n$($output -join "`n")"
    }
}
