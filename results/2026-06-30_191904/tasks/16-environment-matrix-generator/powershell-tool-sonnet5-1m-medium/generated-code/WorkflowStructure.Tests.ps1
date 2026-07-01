#Requires -Modules Pester

# Structure tests for the GitHub Actions workflow itself: these validate the
# workflow YAML shape and lint cleanliness. They run locally (not inside the
# act container) because actionlint is a host-side static analysis tool.

BeforeAll {
    $script:WorkflowPath = Join-Path $PSScriptRoot '.github/workflows/environment-matrix-generator.yml'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -SkipPublisherCheck -Scope CurrentUser
    }
    Import-Module powershell-yaml -Force

    $script:WorkflowYaml = Get-Content $script:WorkflowPath -Raw | ConvertFrom-Yaml
}

Describe 'Environment Matrix Generator workflow structure' {
    It 'exists at the expected path' {
        Test-Path $script:WorkflowPath | Should -Be $true
    }

    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        # YAML key "on" is parsed as boolean $true by some parsers; support both.
        $onKey = if ($script:WorkflowYaml.Contains('on')) { 'on' } else { 'True' }
        $triggers = $script:WorkflowYaml[$onKey]

        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
        $triggers.Keys | Should -Contain 'schedule'
    }

    It 'defines the test, generate-matrix, and build jobs with the expected dependency chain' {
        $jobs = $script:WorkflowYaml['jobs']

        $jobs.Keys | Should -Contain 'test'
        $jobs.Keys | Should -Contain 'generate-matrix'
        $jobs.Keys | Should -Contain 'build'

        $jobs['generate-matrix']['needs'] | Should -Be 'test'
        $jobs['build']['needs'] | Should -Be 'generate-matrix'
    }

    It 'restricts permissions to read-only contents access' {
        $script:WorkflowYaml['permissions']['contents'] | Should -Be 'read'
    }

    It 'references the matrix generator script and test suite that exist on disk' {
        $testJobSteps = $script:WorkflowYaml['jobs']['test']['steps']
        $runSteps = ($testJobSteps | Where-Object { $_.Contains('run') }).run -join "`n"

        $runSteps | Should -Match 'MatrixGenerator\.Tests\.ps1'
        Test-Path (Join-Path $PSScriptRoot 'MatrixGenerator.Tests.ps1') | Should -Be $true

        $generateSteps = $script:WorkflowYaml['jobs']['generate-matrix']['steps']
        $generateRun = ($generateSteps | Where-Object { $_.Contains('run') }).run -join "`n"
        $generateRun | Should -Match 'Generate-Matrix\.ps1'
        Test-Path (Join-Path $PSScriptRoot 'Generate-Matrix.ps1') | Should -Be $true
    }

    It 'uses shell: pwsh on every run step, per PowerShell-mode guidance' {
        $allSteps = $script:WorkflowYaml['jobs'].Values | ForEach-Object { $_['steps'] } | Where-Object { $_ }
        $runSteps = $allSteps | Where-Object { $_.Contains('run') }

        foreach ($step in $runSteps) {
            $step['shell'] | Should -Be 'pwsh'
        }
    }

    It 'passes actionlint with no errors' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this host'
            return
        }

        & actionlint $script:WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
