<#
.SYNOPSIS
    Structure tests for .github/workflows/semantic-version-bumper.yml.

.DESCRIPTION
    Verifies (without Docker):
      * the YAML parses and has the expected triggers/jobs/steps
      * every script/path the workflow references actually exists
      * actionlint passes (exit code 0)
    Tagged 'Workflow' so the CI job (which lacks actionlint) can exclude it;
    these run locally as part of the full `Invoke-Pester` suite.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'semantic-version-bumper.yml'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Yaml = ConvertFrom-Yaml (Get-Content $WorkflowPath -Raw)

    # YAML 1.1 parsers may read the "on" key as boolean $true; accept both.
    $script:Triggers = if ($Yaml.Contains('on')) { $Yaml['on'] } else { $Yaml[$true] }
}

Describe 'Workflow structure' -Tag 'Workflow' {
    It 'exists at the expected path' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'triggers on push and workflow_dispatch' {
        $Triggers.Keys | Should -Contain 'push'
        $Triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'restricts the GITHUB_TOKEN to read-only contents permission' {
        $Yaml['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines the test and bump jobs, with bump depending on test' {
        $Yaml['jobs'].Keys | Should -Contain 'test'
        $Yaml['jobs'].Keys | Should -Contain 'bump'
        $Yaml['jobs']['bump']['needs'] | Should -Be 'test'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        foreach ($job in $Yaml['jobs'].Values) {
            $job['steps'][0]['uses'] | Should -Be 'actions/checkout@v4'
        }
    }

    It 'runs every run: step with shell: pwsh' {
        foreach ($job in $Yaml['jobs'].Values) {
            foreach ($step in $job['steps']) {
                if ($step.Contains('run')) {
                    $step['shell'] | Should -Be 'pwsh'
                }
            }
        }
    }

    It 'references script and test paths that exist on disk' {
        $bumpRun = (@($Yaml['jobs']['bump']['steps'] | Where-Object { $_.Contains('run') }) |
            ForEach-Object { $_['run'] }) -join "`n"
        $bumpRun | Should -Match ([regex]::Escape('./src/Invoke-VersionBump.ps1'))
        Test-Path (Join-Path $RepoRoot 'src' 'Invoke-VersionBump.ps1') | Should -BeTrue

        $testRun = (@($Yaml['jobs']['test']['steps'] | Where-Object { $_.Contains('run') }) |
            ForEach-Object { $_['run'] }) -join "`n"
        $testRun | Should -Match 'tests/unit'
        Test-Path (Join-Path $RepoRoot 'tests' 'unit') | Should -BeTrue
    }

    It 'uses env defaults that exist in the repository' {
        Test-Path (Join-Path $RepoRoot $Yaml['env']['VERSION_FILE']) | Should -BeTrue
        Test-Path (Join-Path $RepoRoot $Yaml['env']['COMMIT_LOG_FILE']) | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        actionlint $WorkflowPath 2>&1 | Out-String | Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 0
    }
}
