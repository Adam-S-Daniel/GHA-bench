#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Structural tests for the GitHub Actions workflow: parses the YAML (not
# just grepping for strings) and checks triggers/jobs/steps, confirms the
# workflow references files that actually exist in the repo, and confirms
# actionlint is satisfied.

BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $WorkflowPath = Join-Path $RepoRoot '.github/workflows/secret-rotation-validator.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -SkipPublisherCheck -Scope CurrentUser
    }
    Import-Module powershell-yaml

    $script:WorkflowYaml = Get-Content -Path $WorkflowPath -Raw | ConvertFrom-Yaml
    $script:WorkflowRaw = Get-Content -Path $WorkflowPath -Raw
}

Describe 'Secret rotation validator workflow structure' {

    It 'exists at the expected path' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'triggers on push, pull_request, schedule and workflow_dispatch' {
        $triggers = $WorkflowYaml['on']

        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers['schedule'][0]['cron'] | Should -Not -BeNullOrEmpty
    }

    It 'requests only read access to repository contents' {
        $WorkflowYaml['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the unit-tests and rotation-report jobs' {
        $WorkflowYaml['jobs'].Keys | Should -Contain 'unit-tests'
        $WorkflowYaml['jobs'].Keys | Should -Contain 'rotation-report'
    }

    It 'runs the rotation-report job only after unit-tests succeeds' {
        $WorkflowYaml['jobs']['rotation-report']['needs'] | Should -Be 'unit-tests'
    }

    It 'runs every job on ubuntu-latest' {
        foreach ($jobName in $WorkflowYaml['jobs'].Keys) {
            $WorkflowYaml['jobs'][$jobName]['runs-on'] | Should -Be 'ubuntu-latest'
        }
    }

    It 'uses shell: pwsh for every scripted step (not pwsh -Command/-File from bash)' {
        foreach ($jobName in $WorkflowYaml['jobs'].Keys) {
            foreach ($step in $WorkflowYaml['jobs'][$jobName]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh'
                }
            }
        }
    }

    It 'references the CLI script and module at paths that exist in the repo' {
        $WorkflowRaw | Should -Match ([regex]::Escape('scripts/Invoke-RotationCheck.ps1'))
        Test-Path (Join-Path $RepoRoot 'scripts/Invoke-RotationCheck.ps1') | Should -BeTrue

        $WorkflowRaw | Should -Match ([regex]::Escape('./Tests'))
        Test-Path (Join-Path $RepoRoot 'Tests') | Should -BeTrue

        Test-Path (Join-Path $RepoRoot 'SecretRotationValidator.psm1') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'secrets-config.json') | Should -BeTrue
    }

    It 'pins third-party actions to a version tag' {
        $actionUses = [regex]::Matches($WorkflowRaw, 'uses:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value }

        $actionUses | Should -Not -BeNullOrEmpty
        foreach ($action in $actionUses) {
            $action | Should -Match '@v\d'
        }
    }

    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        $output = & actionlint $WorkflowPath 2>&1
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }
}
