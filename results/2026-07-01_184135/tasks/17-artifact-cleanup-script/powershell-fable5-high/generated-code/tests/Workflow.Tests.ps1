<#
.SYNOPSIS
    Structure tests for the GitHub Actions workflow.

.DESCRIPTION
    Parses .github/workflows/artifact-cleanup-script.yml as YAML and asserts
    the expected structure (triggers, permissions, jobs, steps), verifies the
    files the workflow references actually exist, and asserts actionlint
    passes with exit code 0.

    These run on the host (not inside the act container) because they need
    actionlint and the powershell-yaml module.
#>

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop

    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:Workflow     = if (Test-Path $script:WorkflowPath) {
        ConvertFrom-Yaml (Get-Content $script:WorkflowPath -Raw)
    } else { $null }
}

Describe 'Workflow file' {
    It 'exists at .github/workflows/artifact-cleanup-script.yml' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid YAML with a name' {
        $script:Workflow | Should -Not -BeNullOrEmpty
        $script:Workflow.name | Should -Not -BeNullOrEmpty
    }
}

Describe 'Workflow triggers' {
    # NOTE: YAML parses the bare key `on:` as boolean true, so the trigger
    # map lands under key $true in powershell-yaml.
    BeforeAll {
        $script:Triggers = $script:Workflow[$true] ?? $script:Workflow['on']
    }

    It 'defines push, schedule and workflow_dispatch triggers' {
        $script:Triggers.Keys | Should -Contain 'push'
        $script:Triggers.Keys | Should -Contain 'schedule'
        $script:Triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'schedules a valid cron expression' {
        $script:Triggers['schedule'][0]['cron'] | Should -Match '^([\d*/,-]+\s+){4}[\d*/,-]+$'
    }
}

Describe 'Workflow jobs and steps' {
    It 'restricts permissions to contents: read' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }

    It 'has a test job and a cleanup-plan job that depends on it' {
        $script:Workflow.jobs.Keys | Should -Contain 'test'
        $script:Workflow.jobs.Keys | Should -Contain 'cleanup-plan'
        $script:Workflow.jobs['cleanup-plan'].needs | Should -Be 'test'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($job in $script:Workflow.jobs.Values) {
            $uses = @($job.steps | Where-Object { $_.ContainsKey('uses') } | ForEach-Object { $_.uses })
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'runs every run: step under shell: pwsh' {
        foreach ($job in $script:Workflow.jobs.Values) {
            foreach ($step in ($job.steps | Where-Object { $_.ContainsKey('run') })) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'runs the Pester suite in the test job' {
        $runs = ($script:Workflow.jobs['test'].steps | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $runs | Should -Match 'Invoke-Pester'
        $runs | Should -Match 'tests/ArtifactCleanup\.Tests\.ps1'
    }

    It 'invokes the cleanup script in the cleanup-plan job' {
        $runs = ($script:Workflow.jobs['cleanup-plan'].steps | Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_.run }) -join "`n"
        $runs | Should -Match 'Invoke-ArtifactCleanup\.ps1'
    }
}

Describe 'Workflow file references' {
    It 'references files that exist in the repository' {
        foreach ($relative in @(
            'Invoke-ArtifactCleanup.ps1',
            'ArtifactCleanup.psm1',
            'tests/ArtifactCleanup.Tests.ps1',
            'fixtures/artifacts.json',
            'fixtures/case1.json',
            'fixtures/case2.json'
        )) {
            Test-Path (Join-Path $script:RepoRoot $relative) | Should -BeTrue -Because "$relative is used by the workflow or its tests"
        }
    }

    It 'points FIXTURE_PATH at an existing fixture' {
        $fixture = $script:Workflow.env['FIXTURE_PATH']
        $fixture | Should -Not -BeNullOrEmpty
        Test-Path (Join-Path $script:RepoRoot $fixture) | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ("actionlint output: " + ($output -join "`n"))
    }
}
