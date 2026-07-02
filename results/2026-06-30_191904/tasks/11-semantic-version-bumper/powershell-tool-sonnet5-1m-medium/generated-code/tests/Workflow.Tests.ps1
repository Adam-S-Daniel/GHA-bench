#Requires -Modules Pester

# Structural checks for the GitHub Actions workflow itself: valid YAML,
# expected triggers/jobs/steps, correct script references, and a clean
# actionlint run. These are static checks; the actual behavioural
# assertions (exact version bumps) are driven through `act` by
# tests/Run-ActTests.ps1.

BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/semantic-version-bumper.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module powershell-yaml -Force

    $script:WorkflowYaml = Get-Content -Path $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Workflow file structure' {

    It 'exists at .github/workflows/semantic-version-bumper.yml' {
        Test-Path -Path $script:WorkflowPath | Should -BeTrue
    }

    It 'parses as valid YAML' {
        $script:WorkflowYaml | Should -Not -BeNullOrEmpty
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        # The YAML parser folds the "on:" key to boolean True under
        # PowerShell-Yaml; normalize to a string key lookup either way.
        $onKey = $script:WorkflowYaml.Keys | Where-Object { $_ -eq 'on' -or $_ -eq $true }
        $on = $script:WorkflowYaml[$onKey]
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
        $on.Keys | Should -Contain 'schedule'
    }

    It 'defines the test and bump-version jobs' {
        $script:WorkflowYaml.jobs.Keys | Should -Contain 'test'
        $script:WorkflowYaml.jobs.Keys | Should -Contain 'bump-version'
    }

    It 'makes bump-version depend on test' {
        $script:WorkflowYaml.jobs['bump-version'].needs | Should -Be 'test'
    }

    It 'runs each job on ubuntu-latest' {
        $script:WorkflowYaml.jobs['test']['runs-on'] | Should -Be 'ubuntu-latest'
        $script:WorkflowYaml.jobs['bump-version']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'declares read-only top-level permissions' {
        $script:WorkflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($jobName in @('test', 'bump-version')) {
            $checkoutSteps = $script:WorkflowYaml.jobs[$jobName].steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }
            $checkoutSteps | Should -Not -BeNullOrEmpty
        }
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($jobName in $script:WorkflowYaml.jobs.Keys) {
            $runSteps = $script:WorkflowYaml.jobs[$jobName].steps | Where-Object { $_.run }
            foreach ($step in $runSteps) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }
}

Describe 'Workflow script references' {
    It 'references Invoke-VersionBump.ps1, which exists in the repo root' {
        $bumpStep = $script:WorkflowYaml.jobs['bump-version'].steps | Where-Object { $_.run -match 'Invoke-VersionBump\.ps1' }
        $bumpStep | Should -Not -BeNullOrEmpty
        Test-Path -Path (Join-Path $script:RepoRoot 'Invoke-VersionBump.ps1') | Should -BeTrue
    }

    It 'references the VersionBumper.psm1 module, which exists in the repo root' {
        Test-Path -Path (Join-Path $script:RepoRoot 'VersionBumper.psm1') | Should -BeTrue
    }

    It 'references the Pester test suite, which exists on disk' {
        $testStep = $script:WorkflowYaml.jobs['test'].steps | Where-Object { $_.run -match 'VersionBumper\.Tests\.ps1' }
        $testStep | Should -Not -BeNullOrEmpty
        Test-Path -Path (Join-Path $script:RepoRoot 'tests/VersionBumper.Tests.ps1') | Should -BeTrue
    }

    It 'references a commit log fixture that exists on disk' {
        Test-Path -Path (Join-Path $script:RepoRoot 'fixtures/commits.txt') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
