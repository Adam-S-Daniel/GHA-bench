# Workflow structure tests: validate the GitHub Actions YAML itself
# (triggers/jobs/steps, referenced file paths, actionlint pass).
# These run locally with Pester -- they do not invoke `act`.

BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:workflowPath = Join-Path $PSScriptRoot '..' '.github' 'workflows' 'dependency-license-checker.yml'
    $script:workflowYaml = ConvertFrom-Yaml (Get-Content -LiteralPath $script:workflowPath -Raw)
}

Describe 'dependency-license-checker.yml structure' {
    It 'exists on disk' {
        Test-Path -LiteralPath $script:workflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, workflow_dispatch, and schedule triggers' {
        # YAML key "on" is parsed as boolean $true by some parsers; powershell-yaml keeps it as string key "on".
        $onSection = $script:workflowYaml['on']
        $onSection.Keys | Should -Contain 'push'
        $onSection.Keys | Should -Contain 'pull_request'
        $onSection.Keys | Should -Contain 'workflow_dispatch'
        $onSection.Keys | Should -Contain 'schedule'
    }

    It 'defines the license-check job on ubuntu-latest' {
        $script:workflowYaml.jobs.Keys | Should -Contain 'license-check'
        $script:workflowYaml.jobs['license-check']['runs-on'] | Should -Be 'ubuntu-latest'
    }

    It 'declares read-only contents permissions' {
        $script:workflowYaml.permissions.contents | Should -Be 'read'
    }

    It 'checks out the repository using actions/checkout@v4' {
        $steps = $script:workflowYaml.jobs['license-check'].steps
        ($steps | Where-Object { $_.uses -eq 'actions/checkout@v4' }) | Should -Not -BeNullOrEmpty
    }

    It 'has a step that runs the Pester test suite' {
        $steps = $script:workflowYaml.jobs['license-check'].steps
        ($steps | Where-Object { $_.run -match 'Invoke-Pester' }) | Should -Not -BeNullOrEmpty
    }

    It 'has a step that invokes Check-Licenses.ps1' {
        $steps = $script:workflowYaml.jobs['license-check'].steps
        ($steps | Where-Object { $_.run -match 'Check-Licenses\.ps1' }) | Should -Not -BeNullOrEmpty
    }

    It 'uses shell: pwsh for PowerShell steps' {
        $steps = $script:workflowYaml.jobs['license-check'].steps
        $pwshSteps = $steps | Where-Object { $_.run -match 'Invoke-Pester|Check-Licenses' }
        foreach ($step in $pwshSteps) {
            $step.shell | Should -Be 'pwsh'
        }
    }
}

Describe 'dependency-license-checker.yml referenced files exist' {
    It 'references an existing Check-Licenses.ps1 script' {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Check-Licenses.ps1'
        Test-Path -LiteralPath $scriptPath | Should -BeTrue
    }

    It 'references an existing tests directory' {
        $testsPath = Join-Path $PSScriptRoot '..' 'tests'
        Test-Path -LiteralPath $testsPath | Should -BeTrue
    }

    It 'references existing fixture files used by the env block' {
        (Join-Path $PSScriptRoot '..' 'fixtures' 'package.json') | Should -Exist
        (Join-Path $PSScriptRoot '..' 'fixtures' 'license-policy.json') | Should -Exist
        (Join-Path $PSScriptRoot '..' 'fixtures' 'mock-licenses.json') | Should -Exist
    }
}

Describe 'dependency-license-checker.yml actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $output = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
