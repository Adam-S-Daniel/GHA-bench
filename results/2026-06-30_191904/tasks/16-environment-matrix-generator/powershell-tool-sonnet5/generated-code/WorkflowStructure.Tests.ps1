<#
    Structural tests for the GitHub Actions workflow file itself.

    These tests do NOT invoke the environment matrix generator's own logic --
    they only parse the workflow YAML and check static facts about it (the
    file's own testing policy reserves logic verification for the act-driven
    pipeline in ActPipeline.Tests.ps1). Because of that, this file is safe to
    run directly with Invoke-Pester on the host.
#>

BeforeAll {
    $script:RepoRoot = $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/environment-matrix-generator.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        throw "The 'powershell-yaml' module is required to parse the workflow file for these tests."
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $script:WorkflowYaml = Get-Content -Path $WorkflowPath -Raw
    $script:Workflow = ConvertFrom-Yaml -Yaml $WorkflowYaml -Ordered
}

Describe 'Workflow file existence and syntax' {
    It 'exists at .github/workflows/environment-matrix-generator.yml' {
        Test-Path $WorkflowPath | Should -Be $true
    }

    It 'parses as valid YAML' {
        $Workflow | Should -Not -BeNullOrEmpty
    }
}

Describe 'Workflow triggers' {
    It 'defines an "on" section' {
        # YAML parsers commonly read the bare key "on" as the boolean $true.
        $onKey = if ($Workflow.Contains('on')) { 'on' } elseif ($Workflow.Contains($true)) { $true } else { $null }
        $onKey | Should -Not -BeNullOrEmpty
        $script:triggers = $Workflow[$onKey]
    }

    It 'triggers on push' {
        $triggers.Contains('push') | Should -Be $true
    }

    It 'triggers on pull_request' {
        $triggers.Contains('pull_request') | Should -Be $true
    }

    It 'triggers on workflow_dispatch' {
        $triggers.Contains('workflow_dispatch') | Should -Be $true
    }

    It 'triggers on a schedule' {
        $triggers.Contains('schedule') | Should -Be $true
        $triggers['schedule'][0]['cron'] | Should -Be '0 6 * * 1'
    }
}

Describe 'Workflow permissions and environment' {
    It 'declares read-only contents permissions' {
        $Workflow['permissions']['contents'] | Should -Be 'read'
    }

    It 'declares environment variables used by the generator steps' {
        $Workflow['env']['CONFIG_DIR'] | Should -Be 'fixtures'
        $Workflow['env']['MATRIX_MAX_SIZE'] | Should -Be '256'
    }
}

Describe 'Workflow jobs and dependencies' {
    It 'defines the test, generate, and use-matrix jobs' {
        $Workflow['jobs'].Contains('test') | Should -Be $true
        $Workflow['jobs'].Contains('generate') | Should -Be $true
        $Workflow['jobs'].Contains('use-matrix') | Should -Be $true
    }

    It 'has generate depend on test' {
        $Workflow['jobs']['generate']['needs'] | Should -Be 'test'
    }

    It 'has use-matrix depend on generate' {
        $Workflow['jobs']['use-matrix']['needs'] | Should -Be 'generate'
    }

    It 'checks out the repository with actions/checkout@v4 in test and generate' {
        foreach ($jobName in @('test', 'generate')) {
            $steps = $Workflow['jobs'][$jobName]['steps']
            ($steps | Where-Object { $_['uses'] -eq 'actions/checkout@v4' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($jobName in $Workflow['jobs'].Keys) {
            $steps = $Workflow['jobs'][$jobName]['steps']
            foreach ($step in $steps) {
                if ($step.Contains('run')) {
                    $step['shell'] | Should -Be 'pwsh'
                }
            }
        }
    }
}

Describe 'Workflow references real project files' {
    It 'references EnvironmentMatrixGenerator.ps1, and the file exists' {
        $WorkflowYaml | Should -Match 'EnvironmentMatrixGenerator\.ps1'
        Test-Path (Join-Path $RepoRoot 'EnvironmentMatrixGenerator.ps1') | Should -Be $true
    }

    It 'references EnvironmentMatrixGenerator.Tests.ps1, and the file exists' {
        $WorkflowYaml | Should -Match 'EnvironmentMatrixGenerator\.Tests\.ps1'
        Test-Path (Join-Path $RepoRoot 'EnvironmentMatrixGenerator.Tests.ps1') | Should -Be $true
    }

    It 'references each fixture file it uses, and those files exist' {
        foreach ($fixture in @('basic-config.json', 'excludes-config.json', 'includes-config.json')) {
            $WorkflowYaml | Should -Match ([regex]::Escape($fixture))
            Test-Path (Join-Path $RepoRoot "fixtures/$fixture") | Should -Be $true
        }
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            throw "actionlint is required on PATH to run this test."
        }

        $output = & actionlint $WorkflowPath 2>&1
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0 -Because ($output -join "`n")
    }
}
