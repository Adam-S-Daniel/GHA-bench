# Workflow.Tests.ps1
# Structural tests for the GitHub Actions workflow file. These run locally
# (not inside act): they parse the YAML, assert the expected triggers/jobs/
# steps, confirm the workflow references real script files, and confirm
# actionlint passes. Run with Invoke-Pester alongside the unit tests.

BeforeAll {
    $script:Root         = $PSScriptRoot
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/artifact-cleanup-script.yml'
    Import-Module powershell-yaml -ErrorAction Stop
    $script:Yaml = ConvertFrom-Yaml (Get-Content -LiteralPath $script:WorkflowPath -Raw)
    $script:Text = Get-Content -LiteralPath $script:WorkflowPath -Raw
}

Describe 'Workflow file - existence & validity' {
    It 'exists' {
        Test-Path -LiteralPath $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow file - triggers' {
    # YAML maps the `on:` key; PowerShell-yaml parses the bare `true` key name
    # ('on') so we read it back via the parsed object.
    It 'declares push, pull_request, schedule and workflow_dispatch' {
        $on = $script:Yaml['on']
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'has a cron schedule' {
        $script:Text | Should -Match "cron:\s*'0 3 \* \* \*'"
    }
}

Describe 'Workflow file - jobs & dependencies' {
    It 'defines test and cleanup-plan jobs' {
        $script:Yaml.jobs.Keys | Should -Contain 'test'
        $script:Yaml.jobs.Keys | Should -Contain 'cleanup-plan'
    }

    It 'makes cleanup-plan depend on test' {
        $script:Yaml.jobs['cleanup-plan'].needs | Should -Be 'test'
    }

    It 'sets least-privilege permissions (contents: read)' {
        $script:Yaml.permissions.contents | Should -Be 'read'
    }

    It 'defines a FIXTURE_FILE environment variable' {
        $script:Yaml.env.Keys | Should -Contain 'FIXTURE_FILE'
    }
}

Describe 'Workflow file - steps reference real files' {
    It 'checks out the repo with actions/checkout@v4' {
        $script:Text | Should -Match 'actions/checkout@v4'
    }

    It 'invokes Invoke-Cleanup.ps1, which exists' {
        $script:Text | Should -Match 'Invoke-Cleanup\.ps1'
        Test-Path (Join-Path $script:Root 'Invoke-Cleanup.ps1') | Should -BeTrue
    }

    It 'references the engine module, which exists' {
        $script:Text | Should -Match 'ArtifactCleanup\.psm1'
        Test-Path (Join-Path $script:Root 'ArtifactCleanup.psm1') | Should -BeTrue
    }

    It 'runs Pester against the unit test file, which exists' {
        $script:Text | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $script:Root 'ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }

    It 'uses shell: pwsh for run steps (not bash-invoked pwsh)' {
        $script:Text | Should -Match 'shell:\s*pwsh'
    }
}
