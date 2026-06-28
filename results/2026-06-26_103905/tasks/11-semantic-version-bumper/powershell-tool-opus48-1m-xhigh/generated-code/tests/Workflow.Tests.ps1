# Workflow.Tests.ps1
#
# Host-side structural tests for the GitHub Actions workflow. These run with
# Invoke-Pester on the host (where actionlint + powershell-yaml are available);
# they are NOT executed inside the act container.
#
# They (1) parse the YAML and assert the expected triggers/jobs/steps,
# (2) verify the workflow references script files that actually exist, and
# (3) assert actionlint validates the workflow cleanly.

BeforeAll {
    $script:Root         = Split-Path -Parent $PSScriptRoot
    $script:WorkflowPath = Join-Path $script:Root '.github/workflows/semantic-version-bumper.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Raw = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:Wf  = $script:Raw | ConvertFrom-Yaml
}

Describe 'Workflow file' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'is valid parseable YAML' {
        $script:Wf | Should -Not -BeNullOrEmpty
        $script:Wf.Keys | Should -Contain 'jobs'
    }
}

Describe 'Triggers' {
    BeforeAll { $script:on = $script:Wf['on'] }

    It 'defines the required trigger events' {
        $script:on.Keys | Should -Contain 'push'
        $script:on.Keys | Should -Contain 'pull_request'
        $script:on.Keys | Should -Contain 'workflow_dispatch'
        $script:on.Keys | Should -Contain 'schedule'
    }

    It 'schedules a cron entry' {
        $script:on['schedule'][0]['cron'] | Should -Match '^\s*\S+ \S+ \S+ \S+ \S+\s*$'
    }

    It 'exposes a workflow_dispatch input for the commit log' {
        $script:on['workflow_dispatch']['inputs'].Keys | Should -Contain 'commit_log_file'
    }
}

Describe 'Permissions and environment' {
    It 'declares least-privilege permissions' {
        $script:Wf['permissions']['contents'] | Should -Be 'read'
    }

    It 'sets the commit-log and changelog environment variables' {
        $script:Wf['env'].Keys | Should -Contain 'COMMIT_LOG_FILE'
        $script:Wf['env'].Keys | Should -Contain 'CHANGELOG_FILE'
    }
}

Describe 'Jobs and steps' {
    It 'defines a test job and a bump job' {
        $script:Wf['jobs'].Keys | Should -Contain 'test'
        $script:Wf['jobs'].Keys | Should -Contain 'bump'
    }

    It 'makes the bump job depend on the test job' {
        $script:Wf['jobs']['bump']['needs'] | Should -Be 'test'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:Wf['jobs'].Keys) {
            $uses = $script:Wf['jobs'][$jobName]['steps'].uses
            ($uses -contains 'actions/checkout@v4') | Should -BeTrue -Because "job '$jobName' should check out the repo"
        }
    }

    It 'runs every run-step with the pwsh shell' {
        foreach ($jobName in $script:Wf['jobs'].Keys) {
            foreach ($step in $script:Wf['jobs'][$jobName]['steps']) {
                if ($step.ContainsKey('run')) {
                    $step['shell'] | Should -Be 'pwsh' -Because "run-steps in '$jobName' must use pwsh"
                }
            }
        }
    }

    It 'invokes the bumper script in the bump job' {
        $runText = ($script:Wf['jobs']['bump']['steps'] |
            Where-Object { $_.ContainsKey('run') } | ForEach-Object { $_['run'] }) -join "`n"
        $runText | Should -Match 'bump-version\.ps1'
    }
}

Describe 'Referenced files exist on disk' {
    It 'references bump-version.ps1 which exists' {
        $script:Raw | Should -Match 'bump-version\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'bump-version.ps1') | Should -BeTrue
    }

    It 'references the unit test file which exists' {
        $script:Raw | Should -Match 'tests/SemanticVersionBumper\.Tests\.ps1'
        Test-Path -LiteralPath (Join-Path $script:Root 'tests/SemanticVersionBumper.Tests.ps1') | Should -BeTrue
    }

    It 'ships the core library the script depends on' {
        Test-Path -LiteralPath (Join-Path $script:Root 'src/SemanticVersionBumper.ps1') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint is not installed on this host' }

        $output = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
    }
}
