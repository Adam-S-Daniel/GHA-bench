# Structure tests for the GitHub Actions workflow file itself: valid YAML,
# expected triggers/jobs/steps, correct references to files that exist on
# disk, and a clean actionlint run. Fast, local checks - no act/Docker.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github/workflows/environment-matrix-generator.yml'
    $script:WorkflowText = Get-Content -LiteralPath $WorkflowPath -Raw

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = ConvertFrom-Yaml -Yaml $WorkflowText -Ordered
}

Describe 'Environment matrix generator workflow structure' {
    It 'exists on disk' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'parses as valid YAML' {
        { ConvertFrom-Yaml -Yaml $WorkflowText } | Should -Not -Throw
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        # Checked against the raw text rather than the parsed object: YAML 1.1
        # parsers (including powershell-yaml/YamlDotNet) treat the bare `on`
        # key as the boolean `true`, which makes structural access brittle.
        $WorkflowText | Should -Match '(?m)^on:'
        $WorkflowText | Should -Match '(?m)^\s*push:'
        $WorkflowText | Should -Match '(?m)^\s*pull_request:'
        $WorkflowText | Should -Match '(?m)^\s*workflow_dispatch:'
        $WorkflowText | Should -Match '(?m)^\s*schedule:'
        $WorkflowText | Should -Match 'cron:'
    }

    It 'defines least-privilege read-only permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'defines an environment variable used by the steps' {
        $Workflow.env.FIXTURES_DIR | Should -Be 'fixtures'
    }

    It 'defines the expected jobs with a dependency between them' {
        $Workflow.jobs.Keys | Should -Contain 'validate'
        $Workflow.jobs.Keys | Should -Contain 'generate-matrix'
        $Workflow.jobs.'generate-matrix'.needs | Should -Be 'validate'
    }

    It 'checks out the repository in every job' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $usesList = @($Workflow.jobs[$jobName].steps | Where-Object { $_.Contains('uses') } | ForEach-Object { $_.uses })
            $usesList | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'references the module and CLI script that exist on disk' {
        $modulePath = Join-Path $RepoRoot 'EnvironmentMatrixGenerator.psm1'
        $scriptPath = Join-Path $RepoRoot 'Generate-Matrix.ps1'
        Test-Path -LiteralPath $modulePath | Should -BeTrue
        Test-Path -LiteralPath $scriptPath | Should -BeTrue
        $WorkflowText | Should -Match 'EnvironmentMatrixGenerator\.psm1'
        $WorkflowText | Should -Match 'Generate-Matrix\.ps1'
    }

    It 'references fixture files that exist on disk' {
        foreach ($fixture in @('basic.config.json', 'full.config.json', 'max-size-exceeded.config.json')) {
            Test-Path -LiteralPath (Join-Path $RepoRoot "fixtures/$fixture") | Should -BeTrue
            $WorkflowText | Should -Match ([regex]::Escape($fixture))
        }
    }

    It 'uses shell: pwsh for every run step (not pwsh -Command/-File from bash)' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $runSteps = @($Workflow.jobs[$jobName].steps | Where-Object { $_.Contains('run') })
            foreach ($step in $runSteps) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }
        $output = & actionlint $WorkflowPath 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Host ($output | Out-String)
        }
        $exitCode | Should -Be 0
    }
}
