#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Structural tests for the GitHub Actions workflow.

.DESCRIPTION
    These tests run on the host (not inside act) because they need the
    powershell-yaml module and the actionlint binary. They verify that:
      * the workflow parses as valid YAML with the expected triggers/jobs/steps,
      * the workflow references script/config files that actually exist on disk,
      * actionlint validates the workflow with exit code 0.
#>

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml'

    Import-Module powershell-yaml -ErrorAction Stop

    $script:Workflow = Get-Content -Raw -LiteralPath $WorkflowPath | ConvertFrom-Yaml

    # The YAML key 'on' can be parsed as the string 'on' or (under YAML 1.1
    # boolean coercion) as $true. Resolve the trigger map either way.
    $script:Triggers =
        if ($Workflow.Contains('on'))      { $Workflow['on'] }
        elseif ($Workflow.Contains($true)) { $Workflow[$true] }
        else                               { $null }

    # Flatten every step across all jobs for convenient cross-cutting assertions.
    $script:AllSteps = foreach ($jobName in $Workflow.jobs.Keys) {
        foreach ($step in $Workflow.jobs[$jobName].steps) { $step }
    }

    # Locate the actionlint binary (PATH first, then the common ~/.local/bin).
    $script:ActionlintCmd = (Get-Command actionlint -ErrorAction SilentlyContinue)?.Source
    if (-not $ActionlintCmd) {
        $fallback = Join-Path $HOME '.local/bin/actionlint'
        if (Test-Path $fallback) { $ActionlintCmd = $fallback }
    }
}

Describe 'Workflow file' {
    It 'exists on disk' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'has a name' {
        $Workflow.name | Should -Be 'Secret Rotation Validator'
    }

    It 'passes actionlint with exit code 0' {
        $ActionlintCmd | Should -Not -BeNullOrEmpty -Because 'actionlint must be installed to validate the workflow'
        $output = & $ActionlintCmd $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ("actionlint output:`n" + ($output -join "`n"))
    }
}

Describe 'Workflow triggers' {
    It 'defines push, pull_request, schedule and workflow_dispatch' {
        $Triggers | Should -Not -BeNullOrEmpty
        @($Triggers.Keys) | Should -Contain 'push'
        @($Triggers.Keys) | Should -Contain 'pull_request'
        @($Triggers.Keys) | Should -Contain 'schedule'
        @($Triggers.Keys) | Should -Contain 'workflow_dispatch'
    }

    It 'has a cron entry on the schedule trigger' {
        $Triggers.schedule[0].cron | Should -Not -BeNullOrEmpty
    }

    It 'exposes a warning_days workflow_dispatch input' {
        @($Triggers.workflow_dispatch.inputs.Keys) | Should -Contain 'warning_days'
    }
}

Describe 'Workflow permissions and environment' {
    It 'grants least-privilege read-only access to contents' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the SECRETS_CONFIG_PATH environment variable' {
        $Workflow.env.SECRETS_CONFIG_PATH | Should -Be 'secrets.json'
    }
}

Describe 'Workflow jobs and dependencies' {
    It 'defines both the test and report jobs' {
        @($Workflow.jobs.Keys) | Should -Contain 'test'
        @($Workflow.jobs.Keys) | Should -Contain 'report'
    }

    It 'makes the report job depend on the test job' {
        @($Workflow.jobs.report.needs) | Should -Contain 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $Workflow.jobs.test.'runs-on'   | Should -Be 'ubuntu-latest'
        $Workflow.jobs.report.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $uses = $Workflow.jobs[$jobName].steps | ForEach-Object { $_.uses } | Where-Object { $_ }
            $uses | Should -Contain 'actions/checkout@v4' -Because "job '$jobName' should check out the repo"
        }
    }
}

Describe 'Workflow references the project scripts via shell: pwsh' {
    It 'invokes the CLI script from a pwsh step' {
        $cliSteps = $AllSteps | Where-Object {
            $_.shell -eq 'pwsh' -and $_.run -and ($_.run -match 'secret-rotation-validator\.ps1')
        }
        $cliSteps | Should -Not -BeNullOrEmpty
    }

    It 'runs the unit tests from a pwsh step in the test job' {
        $testSteps = $Workflow.jobs.test.steps | Where-Object {
            $_.shell -eq 'pwsh' -and $_.run -and ($_.run -match 'SecretRotationValidator\.Tests\.ps1')
        }
        $testSteps | Should -Not -BeNullOrEmpty
    }
}

Describe 'Workflow references files that exist on disk' {
    It 'the CLI script exists' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'secret-rotation-validator.ps1') | Should -BeTrue
    }
    It 'the core module exists' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'SecretRotationValidator.psm1') | Should -BeTrue
    }
    It 'the referenced unit-test file exists' {
        Test-Path -LiteralPath (Join-Path $RepoRoot 'tests/SecretRotationValidator.Tests.ps1') | Should -BeTrue
    }
    It 'the default config file (SECRETS_CONFIG_PATH) exists' {
        $configPath = $Workflow.env.SECRETS_CONFIG_PATH
        Test-Path -LiteralPath (Join-Path $RepoRoot $configPath) | Should -BeTrue
    }
}
