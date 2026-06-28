#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Workflow-structure tests for .github/workflows/artifact-cleanup-script.yml.

    These genuinely parse the YAML (via powershell-yaml) and assert the
    workflow's shape — triggers, jobs, dependencies, shell, action refs — plus
    that the script paths it references exist and that actionlint passes.

    Tagged 'Workflow': they need actionlint + a YAML parser on the host and must
    NOT run inside the act container. Run locally with:
        Invoke-Pester -Path tests/Workflow.Tests.ps1
#>

BeforeAll {
    $script:Root         = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/artifact-cleanup-script.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Wf = Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Yaml

    # YAML 1.1 can fold the `on:` key into a boolean; look it up tolerantly so
    # the test is robust across powershell-yaml versions.
    $script:Triggers = $null
    foreach ($k in $script:Wf.Keys) {
        if ($k -is [bool] -or "$k".ToLower() -eq 'on') { $script:Triggers = $script:Wf[$k] }
    }
}

Describe 'Artifact cleanup workflow structure' -Tag 'Workflow' {

    It 'exists and parses as YAML' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
        $script:Wf       | Should -Not -BeNullOrEmpty
        $script:Wf.name  | Should -Be 'Artifact Cleanup'
    }

    It 'declares the expected trigger events' {
        $script:Triggers                  | Should -Not -BeNullOrEmpty
        $script:Triggers.Keys             | Should -Contain 'push'
        $script:Triggers.Keys             | Should -Contain 'pull_request'
        $script:Triggers.Keys             | Should -Contain 'schedule'
        $script:Triggers.Keys             | Should -Contain 'workflow_dispatch'
    }

    It 'schedules a weekly cron run' {
        $script:Triggers['schedule'][0]['cron'] | Should -Be '0 3 * * 0'
    }

    It 'defines the test and cleanup jobs' {
        $script:Wf['jobs'].Keys | Should -Contain 'test'
        $script:Wf['jobs'].Keys | Should -Contain 'cleanup'
    }

    It 'makes cleanup depend on the test job' {
        $script:Wf['jobs']['cleanup']['needs'] | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $script:Wf['jobs']['test']['runs-on']    | Should -Be 'ubuntu-latest'
        $script:Wf['jobs']['cleanup']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in 'test', 'cleanup') {
            $uses = $script:Wf['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] } | Where-Object { $_ }
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for every run step (PowerShell mode requirement)' {
        foreach ($jobName in $script:Wf['jobs'].Keys) {
            foreach ($step in $script:Wf['jobs'][$jobName]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "step '$($step['name'])' runs a script"
                }
            }
        }
    }

    It 'sets least-privilege permissions, widened only where needed' {
        $script:Wf['permissions']['contents']            | Should -Be 'read'
        $script:Wf['jobs']['cleanup']['permissions']['actions'] | Should -Be 'write'
    }

    It 'declares the FIXTURE_PATH environment variable' {
        $script:Wf['env']['FIXTURE_PATH'] | Should -Be 'fixtures/artifacts.json'
    }
}

Describe 'Workflow references real, existing files' -Tag 'Workflow' {

    It 'references the unit-test runner, and it exists on disk' {
        $runCmds = $script:Wf['jobs']['test']['steps'] | ForEach-Object { $_['run'] } | Where-Object { $_ }
        ($runCmds -join "`n") | Should -Match 'tools/Run-UnitTests\.ps1'
        Test-Path (Join-Path $script:Root 'tools/Run-UnitTests.ps1') | Should -BeTrue
    }

    It 'references the cleanup CLI, and it exists on disk' {
        $runCmds = $script:Wf['jobs']['cleanup']['steps'] | ForEach-Object { $_['run'] } | Where-Object { $_ }
        ($runCmds -join "`n") | Should -Match 'Invoke-Cleanup\.ps1'
        Test-Path (Join-Path $script:Root 'Invoke-Cleanup.ps1') | Should -BeTrue
    }

    It 'ships the module and default fixture the scripts depend on' {
        Test-Path (Join-Path $script:Root 'ArtifactCleanup.psm1')   | Should -BeTrue
        Test-Path (Join-Path $script:Root 'fixtures/artifacts.json') | Should -BeTrue
    }
}

Describe 'Workflow passes actionlint' -Tag 'Workflow' {

    It 'passes actionlint with exit code 0' {
        $out = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
    }
}
