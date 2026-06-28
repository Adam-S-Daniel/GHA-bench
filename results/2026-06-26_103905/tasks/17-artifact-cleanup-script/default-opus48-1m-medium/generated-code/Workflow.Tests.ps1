# Workflow structure tests: parse the workflow YAML and assert its shape, that
# it references existing script files, and that actionlint passes cleanly.
# These run locally (they do not need act).

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:Raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:Wf  = ConvertFrom-Yaml $script:Raw
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        & actionlint $script:WorkflowPath *> $null
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow triggers' {
    # PowerShell-yaml maps the YAML `on:` key; note YAML may parse it as boolean
    # true, so we check the raw text for the trigger names to be safe.
    It 'triggers on push, pull_request, workflow_dispatch and schedule' {
        $script:Raw | Should -Match '(?m)^\s*push:'
        $script:Raw | Should -Match '(?m)^\s*pull_request:'
        $script:Raw | Should -Match '(?m)^\s*workflow_dispatch:'
        $script:Raw | Should -Match '(?m)^\s*schedule:'
        $script:Raw | Should -Match 'cron:'
    }
}

Describe 'Workflow jobs and dependencies' {
    It 'defines both the test and cleanup jobs' {
        $script:Wf.jobs.Keys | Should -Contain 'test'
        $script:Wf.jobs.Keys | Should -Contain 'cleanup'
    }

    It 'makes cleanup depend on test (job dependency)' {
        $script:Wf.jobs.cleanup.needs | Should -Be 'test'
    }

    It 'declares least-privilege permissions' {
        $script:Wf.permissions.contents | Should -Be 'read'
    }

    It 'sets the SCENARIO_PATH environment variable' {
        $script:Wf.env.SCENARIO_PATH | Should -Be 'fixtures/scenario.json'
    }
}

Describe 'Workflow steps reference real files' {
    It 'uses actions/checkout@v4 in both jobs' {
        ($script:Wf.jobs.test.steps    | Where-Object { $_.uses -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
        ($script:Wf.jobs.cleanup.steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
    }

    It 'references the Pester test file, which exists' {
        $script:Raw | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $PSScriptRoot 'ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }

    It 'references the cleanup CLI script, which exists' {
        $script:Raw | Should -Match 'Invoke-Cleanup\.ps1'
        Test-Path (Join-Path $PSScriptRoot 'Invoke-Cleanup.ps1') | Should -BeTrue
    }

    It 'uses pwsh shell for run steps' {
        ($script:Wf.jobs.test.steps    | Where-Object { $_.shell -eq 'pwsh' }) | Should -Not -BeNullOrEmpty
        ($script:Wf.jobs.cleanup.steps | Where-Object { $_.shell -eq 'pwsh' }) | Should -Not -BeNullOrEmpty
    }
}
