#Requires -Modules Pester

# Structural tests for the GitHub Actions workflow: parses the YAML and
# checks triggers/jobs/steps, verifies referenced script/test paths exist,
# and verifies the workflow passes actionlint.

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $WorkflowPath = Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml'
    $script:WorkflowYaml = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'GitHub Actions workflow structure' {

    It 'exists at the expected path' {
        Test-Path (Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml') | Should -BeTrue
    }

    It 'triggers on push' {
        $WorkflowYaml.on.Keys | Should -Contain 'push'
    }

    It 'triggers on pull_request' {
        $WorkflowYaml.on.Keys | Should -Contain 'pull_request'
    }

    It 'triggers on a schedule' {
        $WorkflowYaml.on.Keys | Should -Contain 'schedule'
        $WorkflowYaml.on.schedule[0].cron | Should -Not -BeNullOrEmpty
    }

    It 'supports manual workflow_dispatch' {
        $WorkflowYaml.on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares minimal (read-only) permissions' {
        $WorkflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'defines a test job and a validate-secrets job' {
        $WorkflowYaml.jobs.Keys | Should -Contain 'test'
        $WorkflowYaml.jobs.Keys | Should -Contain 'validate-secrets'
    }

    It 'runs validate-secrets only after the test job succeeds (job dependency)' {
        $WorkflowYaml.jobs.'validate-secrets'.needs | Should -Be 'test'
    }

    It 'checks out the repository in both jobs using actions/checkout@v4' {
        foreach ($jobName in @('test', 'validate-secrets')) {
            $checkoutStep = $WorkflowYaml.jobs.$jobName.steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }
            $checkoutStep | Should -Not -BeNullOrEmpty -Because "job '$jobName' should check out the repo"
        }
    }

    It 'uses shell: pwsh for all run steps (avoids bash-quoting pitfalls)' {
        foreach ($jobName in $WorkflowYaml.jobs.Keys) {
            foreach ($step in $WorkflowYaml.jobs.$jobName.steps) {
                if ($step.PSObject.Properties.Match('run').Count -gt 0) {
                    $step.shell | Should -Be 'pwsh' -Because "step '$($step.name)' runs a script"
                }
            }
        }
    }

    It 'references the validator script at a path that actually exists' {
        Join-Path $RepoRoot 'SecretRotationValidator.ps1' | Should -Exist
        $allRunText = ($WorkflowYaml.jobs.Values.steps | Where-Object { $_.run } | ForEach-Object { $_.run }) -join "`n"
        $allRunText | Should -Match 'SecretRotationValidator\.ps1'
    }

    It 'references fixture files that actually exist' {
        Join-Path $RepoRoot 'Tests/fixtures/mixed-secrets.json' | Should -Exist
        Join-Path $RepoRoot 'Tests/fixtures/all-healthy-secrets.json' | Should -Exist
    }

    It 'references the unit test files that actually exist' {
        Join-Path $RepoRoot 'Tests/SecretRotationValidator.Tests.ps1' | Should -Exist
        Join-Path $RepoRoot 'Tests/SecretRotationValidatorScript.Tests.ps1' | Should -Exist
    }

    It 'passes actionlint validation' {
        $actionlintPath = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlintPath) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }
        & actionlint (Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml')
        $LASTEXITCODE | Should -Be 0
    }
}
