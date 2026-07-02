# Structural tests for the GitHub Actions workflow: parses the YAML and
# checks triggers/jobs/steps, verifies referenced script paths exist, and
# confirms actionlint passes cleanly.

BeforeAll {
    $script:WorkflowPath = Join-Path $PSScriptRoot '..' '.github' 'workflows' 'secret-rotation-validator.yml'
    $script:RepoRoot = Join-Path $PSScriptRoot '..'

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -ErrorAction Stop
    }
    Import-Module powershell-yaml -Force

    $script:WorkflowYaml = Get-Content -Path $WorkflowPath -Raw
    # YAML parses the bare 'on:' key as boolean key `true` in most parsers;
    # ConvertFrom-Yaml keeps it as string key "on" is NOT guaranteed, so
    # inspect via raw text where needed alongside the parsed object.
    $script:Workflow = ConvertFrom-Yaml -Yaml $WorkflowYaml
}

Describe 'secret-rotation-validator.yml workflow structure' {

    It 'exists on disk' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        $WorkflowYaml | Should -Match '(?m)^on:'
        $WorkflowYaml | Should -Match '(?m)^\s*push:'
        $WorkflowYaml | Should -Match '(?m)^\s*pull_request:'
        $WorkflowYaml | Should -Match '(?m)^\s*workflow_dispatch:'
        $WorkflowYaml | Should -Match '(?m)^\s*schedule:'
    }

    It 'defines the unit-tests and validate-secrets jobs' {
        $Workflow.jobs.Keys | Should -Contain 'unit-tests'
        $Workflow.jobs.Keys | Should -Contain 'validate-secrets'
    }

    It 'makes validate-secrets depend on unit-tests' {
        $Workflow.jobs.'validate-secrets'.needs | Should -Be 'unit-tests'
    }

    It 'checks out the repo in every job' {
        foreach ($jobName in $Workflow.jobs.Keys) {
            $usesList = $Workflow.jobs.$jobName.steps | ForEach-Object { $_.uses }
            $usesList | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'runs steps with shell: pwsh (not pwsh -Command/-File)' {
        $shells = $Workflow.jobs.Values.steps | Where-Object { $_.run } | ForEach-Object { $_.shell }
        $shells | Should -Not -BeNullOrEmpty
        $shells | ForEach-Object { $_ | Should -Be 'pwsh' }
    }

    It 'declares top-level permissions' {
        $Workflow.permissions.contents | Should -Be 'read'
    }

    It 'declares the expected environment variables' {
        $Workflow.env.WARNING_DAYS | Should -Be 14
        $Workflow.env.SECRETS_CONFIG_PATH | Should -Be 'fixtures/sample-secrets.json'
    }

    It 'references the validator script and fixture at paths that exist in the repo' {
        Test-Path (Join-Path $RepoRoot 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'SecretRotationValidator.psm1') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'fixtures' 'sample-secrets.json') | Should -BeTrue
        Test-Path (Join-Path $RepoRoot 'tests') | Should -BeTrue
    }

    It 'passes actionlint with no findings' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed on this machine'
            return
        }

        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
