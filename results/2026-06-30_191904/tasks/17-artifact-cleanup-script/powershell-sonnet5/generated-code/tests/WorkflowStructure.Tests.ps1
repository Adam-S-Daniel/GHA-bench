#Requires -Modules Pester

<#
    Static validation of the GitHub Actions workflow file itself: does it
    parse as valid YAML with the expected triggers/jobs/steps, do the
    scripts it references actually exist, and does actionlint accept it.

    This file runs LOCALLY (via Invoke-Pester), not inside the act
    container -- it is checking the pipeline definition, not exercising the
    cleanup script's own logic (that happens inside the pipeline, see
    ActIntegration.Tests.ps1 and ArtifactCleanup.Tests.ps1 which the
    workflow itself runs).
#>

BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..'
    $script:workflowPath = Join-Path $repoRoot '.github/workflows/artifact-cleanup-script.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:workflowRaw = Get-Content -LiteralPath $script:workflowPath -Raw
    $script:workflow = $script:workflowRaw | ConvertFrom-Yaml -Ordered
}

Describe 'Workflow file structure' {
    It 'exists at the required path' {
        Test-Path -LiteralPath $script:workflowPath | Should -Be $true
    }

    It 'parses as valid YAML' {
        $script:workflow | Should -Not -BeNullOrEmpty
    }

    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        $script:workflow.on.Keys | Should -Contain 'push'
        $script:workflow.on.Keys | Should -Contain 'pull_request'
        $script:workflow.on.Keys | Should -Contain 'workflow_dispatch'
        $script:workflow.on.Keys | Should -Contain 'schedule'
    }

    It 'defines a workflow_dispatch dry_run boolean input' {
        $script:workflow.on.workflow_dispatch.inputs.dry_run.type | Should -Be 'boolean'
    }

    It 'declares top-level read-only permissions' {
        $script:workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines both required jobs' {
        $script:workflow.jobs.Keys | Should -Contain 'unit-tests'
        $script:workflow.jobs.Keys | Should -Contain 'cleanup-simulation'
    }

    It 'makes cleanup-simulation depend on unit-tests (job dependency)' {
        $script:workflow.jobs.'cleanup-simulation'.needs | Should -Be 'unit-tests'
    }

    It 'grants cleanup-simulation the actions:write permission needed to delete artifacts' {
        $script:workflow.jobs.'cleanup-simulation'.permissions.actions | Should -Be 'write'
    }

    It 'defines the default retention policy as environment variables' {
        $env = $script:workflow.jobs.'cleanup-simulation'.env
        $env.DEFAULT_MAX_AGE_DAYS | Should -Not -BeNullOrEmpty
        $env.DEFAULT_MAX_TOTAL_SIZE_BYTES | Should -Not -BeNullOrEmpty
        $env.DEFAULT_KEEP_LATEST_PER_WORKFLOW | Should -Not -BeNullOrEmpty
    }

    It 'checks out the repository in every job' {
        foreach ($jobName in $script:workflow.jobs.Keys) {
            $steps = $script:workflow.jobs[$jobName].steps
            ($steps | Where-Object { $_.uses -like 'actions/checkout@*' }) | Should -Not -BeNullOrEmpty -Because "job '$jobName' should check out the repo"
        }
    }

    It 'pins actions/checkout to v4' {
        $checkoutSteps = $script:workflow.jobs.Values | ForEach-Object { $_.steps } | Where-Object { $_.uses -like 'actions/checkout@*' }
        $checkoutSteps | ForEach-Object { $_.uses | Should -Be 'actions/checkout@v4' }
    }

    It 'uses shell: pwsh for every run step (not pwsh -Command/-File from bash)' {
        $runSteps = $script:workflow.jobs.Values | ForEach-Object { $_.steps } | Where-Object { $_.run }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($step in $runSteps) {
            $step.shell | Should -Be 'pwsh'
        }
    }
}

Describe 'Workflow script references' {
    It 'references the ArtifactCleanup unit test file, and it exists' {
        $script:workflowRaw | Should -Match ([regex]::Escape('./tests/ArtifactCleanup.Tests.ps1'))
        Test-Path (Join-Path $PSScriptRoot 'ArtifactCleanup.Tests.ps1') | Should -Be $true
    }

    It 'references artifact-cleanup.ps1, and it exists' {
        $script:workflowRaw | Should -Match ([regex]::Escape('./artifact-cleanup.ps1'))
        Test-Path (Join-Path $PSScriptRoot '..' 'artifact-cleanup.ps1') | Should -Be $true
    }

    It 'references every fixture scenario file it runs, and each one exists' {
        $fixtureRefs = [regex]::Matches($script:workflowRaw, './fixtures/[\w\-]+\.json') | ForEach-Object { $_.Value } | Select-Object -Unique
        $fixtureRefs.Count | Should -BeGreaterOrEqual 3
        foreach ($ref in $fixtureRefs) {
            $path = Join-Path (Join-Path $PSScriptRoot '..') ($ref -replace '^\./', '')
            Test-Path $path | Should -Be $true -Because "$ref should exist on disk"
        }
    }

    It 'references the ArtifactCleanup module (used transitively by artifact-cleanup.ps1), and it exists' {
        Test-Path (Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1') | Should -Be $true
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }

        $output = & actionlint $script:workflowPath 2>&1
        $exitCode = $LASTEXITCODE
        $output | Out-String | Write-Verbose -Verbose
        $exitCode | Should -Be 0 -Because ($output -join "`n")
    }
}
