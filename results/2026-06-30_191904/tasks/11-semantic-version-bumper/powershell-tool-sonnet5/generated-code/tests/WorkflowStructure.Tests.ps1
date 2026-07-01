# Static checks on .github/workflows/semantic-version-bumper.yml: parses the
# YAML and asserts on its structure (triggers, jobs, steps), verifies every
# script path it references actually exists in the repo, and asserts that
# actionlint passes cleanly.
#
# These are structural/static checks only -- they do not execute the
# workflow. Behavioral verification (does it actually bump versions
# correctly end to end) happens through `act` in tests/WorkflowE2E.Tests.ps1.
#
# Run with:  Invoke-Pester ./tests/WorkflowStructure.Tests.ps1 -Output Detailed

BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'semantic-version-bumper.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content -Path $WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'semantic-version-bumper.yml structure' {

    It 'exists' {
        Test-Path -Path $WorkflowPath -PathType Leaf | Should -BeTrue
    }

    It 'is valid YAML with a name' {
        $Workflow.name | Should -Be 'Semantic Version Bumper'
    }

    It 'triggers on push, pull_request, and workflow_dispatch' {
        # YAML 1.1 parses the bare `on:` key as-is here (powershell-yaml
        # keeps it as the literal string key "on").
        $Workflow.on.Keys | Should -Contain 'push'
        $Workflow.on.Keys | Should -Contain 'pull_request'
        $Workflow.on.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege read-only permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines the test and bump-version jobs' {
        $Workflow.jobs.Keys | Should -Contain 'test'
        $Workflow.jobs.Keys | Should -Contain 'bump-version'
    }

    It 'makes bump-version depend on test via needs' {
        $Workflow.jobs.'bump-version'.needs | Should -Be 'test'
    }

    It 'runs both jobs on ubuntu-latest' {
        $Workflow.jobs.test.'runs-on' | Should -Be 'ubuntu-latest'
        $Workflow.jobs.'bump-version'.'runs-on' | Should -Be 'ubuntu-latest'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $steps = $Workflow.jobs.$jobName.steps
            $checkoutStep = $steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }
            $checkoutStep | Should -Not -BeNullOrEmpty -Because "job '$jobName' should check out the repo"
        }
    }

    It 'uses shell: pwsh for every run step (per PowerShell-mode requirements)' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $runSteps = $Workflow.jobs.$jobName.steps | Where-Object { $_.run }
            foreach ($step in $runSteps) {
                $step.shell | Should -Be 'pwsh' -Because "step '$($step.name)' in job '$jobName' runs a script"
            }
        }
    }

    It 'references the CLI script at a path that exists in the repo' {
        $bumpStep = $Workflow.jobs.'bump-version'.steps | Where-Object { $_.id -eq 'bump' }
        $bumpStep | Should -Not -BeNullOrEmpty
        $bumpStep.run | Should -Match 'Invoke-SemanticVersionBumper\.ps1'

        $scriptPath = Join-Path $RepoRoot 'scripts' 'Invoke-SemanticVersionBumper.ps1'
        Test-Path -Path $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'references Pester test files that exist in the repo' {
        $testStep = $Workflow.jobs.test.steps | Where-Object { $_.run -match 'Invoke-Pester' }
        $testStep | Should -Not -BeNullOrEmpty

        foreach ($match in [regex]::Matches($testStep.run, "'(\./tests/[^']+\.Tests\.ps1)'")) {
            $relativePath = $match.Groups[1].Value
            $fullPath = Join-Path $RepoRoot $relativePath
            Test-Path -Path $fullPath -PathType Leaf | Should -BeTrue -Because "workflow references $relativePath"
        }
    }

    It 'exposes the env vars the CLI script consumes' {
        $Workflow.env.VERSION_FILE_PATH | Should -Not -BeNullOrEmpty
        $Workflow.env.COMMIT_LOG_PATH | Should -Not -BeNullOrEmpty
        $Workflow.env.CHANGELOG_FILE_PATH | Should -Not -BeNullOrEmpty

        Test-Path -Path (Join-Path $RepoRoot $Workflow.env.COMMIT_LOG_PATH) -PathType Leaf | Should -BeTrue
    }
}

Describe 'actionlint' {
    It 'passes cleanly on semantic-version-bumper.yml' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        $actionlint | Should -Not -BeNullOrEmpty -Because 'actionlint must be installed to validate the workflow'

        & $actionlint.Source $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
