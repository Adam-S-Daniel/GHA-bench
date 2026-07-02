<#
.SYNOPSIS
    Structure tests for the GitHub Actions workflow.

.DESCRIPTION
    TDD Cycle 6: written before the workflow file existed.
    - Parses the YAML (via powershell-yaml when available) and checks the
      expected structure: triggers, permissions, jobs, dependencies, steps.
    - Verifies every project file the workflow references actually exists.
    - Asserts `actionlint` passes with exit code 0.
    Tests that need optional tooling (powershell-yaml, actionlint) are
    skipped where the tool is unavailable (e.g. inside the CI container),
    and always run locally where both are installed.
#>

BeforeDiscovery {
    # Availability probes must happen at discovery time so -Skip works.
    $script:hasYamlModule = [bool](Get-Module -ListAvailable powershell-yaml)
    $script:hasActionlint = [bool](Get-Command actionlint -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:workflowPath = Join-Path $root '.github/workflows/dependency-license-checker.yml'
    $script:raw = if (Test-Path $workflowPath) { Get-Content $workflowPath -Raw } else { '' }
}

Describe 'workflow file' {
    It 'exists at .github/workflows/dependency-license-checker.yml' {
        Test-Path $workflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' -Skip:(-not $hasActionlint) {
        actionlint $workflowPath 2>&1 | Out-String | Write-Verbose
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'workflow structure (parsed YAML)' -Skip:(-not $hasYamlModule) {
    BeforeAll {
        Import-Module powershell-yaml
        $script:yaml = ConvertFrom-Yaml $raw
        # YAML 1.1 quirk: an unquoted `on:` key parses as boolean $true.
        $script:triggers = if ($yaml.Contains('on')) { $yaml['on'] } else { $yaml[$true] }
    }

    It 'declares push, pull_request, schedule and workflow_dispatch triggers' {
        $triggers.Keys | Should -Contain 'push'
        $triggers.Keys | Should -Contain 'pull_request'
        $triggers.Keys | Should -Contain 'schedule'
        $triggers.Keys | Should -Contain 'workflow_dispatch'
    }

    It 'restricts permissions to contents: read' {
        $yaml.permissions.contents | Should -Be 'read'
    }

    It 'defines a test job and a license-check job that depends on it' {
        $yaml.jobs.Keys | Should -Contain 'test'
        $yaml.jobs.Keys | Should -Contain 'license-check'
        $yaml.jobs.'license-check'.needs | Should -Be 'test'
    }

    It 'checks out the repository in every job' {
        foreach ($job in $yaml.jobs.Values) {
            @($job.steps | Where-Object { $_.uses -like 'actions/checkout@v4*' }).Count |
                Should -BeGreaterOrEqual 1
        }
    }

    It 'runs all run: steps under shell: pwsh' {
        foreach ($job in $yaml.jobs.Values) {
            foreach ($step in ($job.steps | Where-Object { $_.run })) {
                $step.shell | Should -Be 'pwsh'
            }
        }
    }
}

Describe 'workflow references (paths exist)' {
    It 'references the CLI script and the file exists' {
        $raw | Should -Match ([regex]::Escape('./check-licenses.ps1'))
        Test-Path (Join-Path $root 'check-licenses.ps1') | Should -BeTrue
    }

    It 'runs the Pester unit test files and they exist' {
        $raw | Should -Match ([regex]::Escape('tests/DependencyLicenseChecker.Tests.ps1'))
        Test-Path (Join-Path $root 'tests/DependencyLicenseChecker.Tests.ps1') | Should -BeTrue
    }

    It 'references the fixture config/database files and they exist' {
        foreach ($fixture in 'fixtures/license-config.json', 'fixtures/mock-license-db.json', 'fixtures/package.json') {
            $raw | Should -Match ([regex]::Escape($fixture))
            Test-Path (Join-Path $root $fixture) | Should -BeTrue
        }
    }
}
