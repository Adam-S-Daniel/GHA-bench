#requires -Modules Pester
<#
    WorkflowStructure.Tests.ps1

    Static-structure tests for the GitHub Actions workflow. These assert that:
      * the workflow YAML parses and has the expected triggers/jobs/steps,
      * it references the checker script files using paths that actually exist,
      * it pins actions/checkout@v4,
      * actionlint validates it with exit code 0.

    These run locally (they shell out to actionlint, which is not part of the
    runtime container) and are NOT executed inside the workflow itself.
#>

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/dependency-license-checker.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml
    $script:RawYaml  = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'Workflow file' {

    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'has a human-readable name' {
        $script:Workflow['name'] | Should -Be 'Dependency License Checker'
    }
}

Describe 'Triggers (on:)' {

    It 'defines push, pull_request, schedule and workflow_dispatch triggers' {
        $on = $script:Workflow['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }
}

Describe 'Permissions' {

    It 'grants least-privilege read-only access to contents' {
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
    }
}

Describe 'Jobs' {

    It 'defines a test job and a license-check job' {
        $script:Workflow['jobs'].Keys | Should -Contain 'test'
        $script:Workflow['jobs'].Keys | Should -Contain 'license-check'
    }

    It 'makes license-check depend on the test job' {
        $needs = @($script:Workflow['jobs']['license-check']['needs'])
        $needs | Should -Contain 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Workflow['jobs']['test']['runs-on']          | Should -Be 'ubuntu-latest'
        $script:Workflow['jobs']['license-check']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Workflow['jobs'].Keys) {
            $uses = @($script:Workflow['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] })
            ($uses -contains 'actions/checkout@v4') | Should -BeTrue -Because "$jobName should check out the repo"
        }
    }
}

Describe 'Script references resolve to real files' {

    It 'references files that exist on disk' {
        # The workflow invokes these; make sure the paths are real.
        foreach ($rel in @(
                'Invoke-LicenseCheck.ps1',
                'LicenseChecker.psm1',
                'tests/LicenseChecker.Tests.ps1',
                'config/license-config.json',
                'fixtures/license-db.json'
            )) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $rel) |
                Should -BeTrue -Because "$rel is referenced by the workflow"
        }
    }

    It 'invokes Invoke-LicenseCheck.ps1 and the Pester test file by name' {
        $script:RawYaml | Should -Match 'Invoke-LicenseCheck\.ps1'
        $script:RawYaml | Should -Match 'tests/LicenseChecker\.Tests\.ps1'
    }

    It 'uses shell: pwsh for every run step (per task requirement)' {
        foreach ($jobName in $script:Workflow['jobs'].Keys) {
            foreach ($step in $script:Workflow['jobs'][$jobName]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "run steps in $jobName must use pwsh"
                }
            }
        }
    }
}

Describe 'actionlint validation' {

    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }
        $output = & $actionlint.Source $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
