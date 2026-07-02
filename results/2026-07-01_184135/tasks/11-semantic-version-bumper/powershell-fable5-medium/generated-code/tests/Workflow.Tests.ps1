# Structure tests for the GitHub Actions workflow.
# Parses the YAML, checks triggers/jobs/steps, verifies referenced script
# paths exist, and asserts actionlint passes.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'semantic-version-bumper.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml (Get-Content -Path $WorkflowPath -Raw)
}

Describe 'Workflow file' {
    It 'exists at .github/workflows/semantic-version-bumper.yml' {
        $WorkflowPath | Should -Exist
    }

    It 'parses as valid YAML' {
        $Workflow | Should -Not -BeNullOrEmpty
    }

    It 'passes actionlint' {
        actionlint $WorkflowPath | Out-String | Write-Verbose
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow structure' {
    It 'has push, pull_request and workflow_dispatch triggers' {
        # YAML parses the bare key `on` as boolean True in some parsers;
        # powershell-yaml keeps it as "on".
        $on = $Workflow['on']
        if (-not $on) { $on = $Workflow[$true] }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'restricts permissions to contents: read' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines test and bump jobs' {
        $Workflow.jobs.Keys | Should -Contain 'test'
        $Workflow.jobs.Keys | Should -Contain 'bump'
    }

    It 'makes bump depend on test' {
        $Workflow.jobs.bump.needs | Should -Be 'test'
    }

    It 'checks out the repository in every job' {
        foreach ($job in $Workflow.jobs.Values) {
            ($job.steps | Where-Object { $_.uses -like 'actions/checkout@v4*' }) |
                Should -Not -BeNullOrEmpty
        }
    }

    It 'uses shell: pwsh for every run step' {
        foreach ($job in $Workflow.jobs.Values) {
            foreach ($step in ($job.steps | Where-Object { $_.ContainsKey('run') })) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'runs the Pester test suite in the test job' {
        $runBlocks = ($Workflow.jobs.test.steps | Where-Object { $_.ContainsKey('run') }).run -join "`n"
        $runBlocks | Should -Match 'Invoke-Pester'
        $runBlocks | Should -Match 'tests/VersionBumper\.Tests\.ps1'
    }

    It 'invokes the bump script in the bump job' {
        $runBlocks = ($Workflow.jobs.bump.steps | Where-Object { $_.ContainsKey('run') }).run -join "`n"
        $runBlocks | Should -Match 'Invoke-VersionBump\.ps1'
    }
}

Describe 'Workflow file references' {
    It 'references script and fixture paths that exist in the repo' {
        # Every repo-relative file mentioned in the workflow must exist.
        foreach ($rel in @(
                'Invoke-VersionBump.ps1',
                'tests/VersionBumper.Tests.ps1',
                'fixtures/commits-feat.txt')) {
            Join-Path $RepoRoot $rel | Should -Exist
        }
    }

    It 'has the module the entry script imports' {
        Join-Path $RepoRoot 'src' 'VersionBumper.psm1' | Should -Exist
    }
}
