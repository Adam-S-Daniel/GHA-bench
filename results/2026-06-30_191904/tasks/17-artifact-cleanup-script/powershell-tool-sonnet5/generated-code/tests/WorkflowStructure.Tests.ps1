#Requires -Modules Pester
<#
    Static validation of the GitHub Actions workflow file itself: this suite
    runs on the HOST (not inside act) because it's checking properties of the
    repository/workflow file, not the artifact-cleanup logic. It uses the
    powershell-yaml module to parse the workflow and asserts on its
    structure, then shells out to actionlint for full validation.
#>

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github' 'workflows' 'artifact-cleanup-script.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -SkipPublisherCheck -Scope CurrentUser
    }
    Import-Module powershell-yaml -Force

    $script:WorkflowYaml = Get-Content -Raw -Path $script:WorkflowPath | ConvertFrom-Yaml
}

Describe 'artifact-cleanup-script.yml structure' {

    It 'exists' {
        Test-Path $script:WorkflowPath | Should -Be $true
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        # YAML parses the bareword key `on` as boolean $true -- read via the
        # actual key PowerShell-Yaml assigns it.
        $onKey = $script:WorkflowYaml.Keys | Where-Object { $_ -in @('on', 'On', 'true', 'True') } | Select-Object -First 1
        $triggers = $script:WorkflowYaml[$onKey]

        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'declares read-only top-level permissions' {
        $script:WorkflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'defines an environment variable for the deterministic reference time' {
        $script:WorkflowYaml.env.FIXTURE_NOW | Should -Be '2026-07-01T00:00:00Z'
    }

    It 'has a unit-tests job and a cleanup job' {
        $script:WorkflowYaml.jobs.Keys | Should -Contain 'unit-tests'
        $script:WorkflowYaml.jobs.Keys | Should -Contain 'cleanup'
    }

    It 'has the cleanup job depend on the unit-tests job' {
        $script:WorkflowYaml.jobs.cleanup.needs | Should -Be 'unit-tests'
    }

    It 'runs the cleanup job across a scenario matrix with at least 4 cases' {
        $matrixIncludes = $script:WorkflowYaml.jobs.cleanup.strategy.matrix.include
        $matrixIncludes.Count | Should -BeGreaterOrEqual 4
        ($matrixIncludes | ForEach-Object scenario) | Should -Contain 'age-policy'
        ($matrixIncludes | ForEach-Object scenario) | Should -Contain 'size-policy'
        ($matrixIncludes | ForEach-Object scenario) | Should -Contain 'keep-latest'
        ($matrixIncludes | ForEach-Object scenario) | Should -Contain 'combined-dry-run'
    }

    It 'uses actions/checkout@v4 in every job' {
        foreach ($job in $script:WorkflowYaml.jobs.Values) {
            # Wrap in @() -- Where-Object over Hashtable-valued steps can return
            # a single bare Hashtable rather than a 1-element array, and a bare
            # Hashtable's .Count reflects its KEY count, not "how many steps".
            $checkoutSteps = @($job.steps | Where-Object { $_.uses -like 'actions/checkout@*' })
            $checkoutSteps.Count | Should -BeGreaterOrEqual 1
            $checkoutSteps[0].uses | Should -Be 'actions/checkout@v4'
        }
    }

    It 'uses shell: pwsh for every run step (not pwsh -Command/-File from bash)' {
        foreach ($job in $script:WorkflowYaml.jobs.Values) {
            $runSteps = @($job.steps | Where-Object { $_.Keys -contains 'run' })
            $runSteps.Count | Should -BeGreaterOrEqual 1
            foreach ($step in $runSteps) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'references the CLI script and module at paths that exist in the repo' {
        $script:WorkflowYaml.jobs.cleanup.steps.run -join "`n" | Should -Match 'Invoke-ArtifactCleanup\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'Invoke-ArtifactCleanup.ps1') | Should -Be $true
        Test-Path (Join-Path $script:RepoRoot 'ArtifactCleanup.psm1') | Should -Be $true
    }

    It 'references the fixture file at a path that exists in the repo' {
        $script:WorkflowYaml.env.ARTIFACTS_FIXTURE | Should -Be 'fixtures/sample-artifacts.json'
        Test-Path (Join-Path $script:RepoRoot 'fixtures' 'sample-artifacts.json') | Should -Be $true
    }

    It 'references the unit test files at paths that exist in the repo' {
        $unitTestStep = $script:WorkflowYaml.jobs.'unit-tests'.steps.run -join "`n"
        $unitTestStep | Should -Match 'ArtifactCleanup\.Tests\.ps1'
        $unitTestStep | Should -Match 'InvokeArtifactCleanup\.Tests\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'tests' 'ArtifactCleanup.Tests.ps1') | Should -Be $true
        Test-Path (Join-Path $script:RepoRoot 'tests' 'InvokeArtifactCleanup.Tests.ps1') | Should -Be $true
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlintPath = (Get-Command actionlint -ErrorAction SilentlyContinue)
        if (-not $actionlintPath) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }

        $output = & actionlint $script:WorkflowPath 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Output ($output -join "`n")
        }
        $exitCode | Should -Be 0
    }
}
