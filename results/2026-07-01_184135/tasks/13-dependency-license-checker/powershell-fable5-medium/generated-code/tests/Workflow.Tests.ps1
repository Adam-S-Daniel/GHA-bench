<#
.SYNOPSIS
    Structure tests for the GitHub Actions workflow.

.DESCRIPTION
    Validates (without running act):
      * actionlint passes with exit code 0
      * the YAML parses and has the expected triggers, jobs, and steps
      * every file path the workflow references actually exists

    The workflow YAML is parsed with a minimal line-based reader (no YAML
    module dependency) — assertions are on well-known literal lines/keys.
#>

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/dependency-license-checker.yml'
    $script:WorkflowText = Get-Content -LiteralPath $script:WorkflowPath -Raw
    $script:WorkflowLines = Get-Content -LiteralPath $script:WorkflowPath
}

Describe 'Workflow file' {
    It 'exists at the required path' {
        Test-Path $script:WorkflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        # actionlint is expected on PATH (pre-installed on the CI host).
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow structure' {
    It 'declares push, pull_request, workflow_dispatch and schedule triggers' {
        $script:WorkflowText | Should -Match '(?m)^\s*push:'
        $script:WorkflowText | Should -Match '(?m)^\s*pull_request:'
        $script:WorkflowText | Should -Match '(?m)^\s*workflow_dispatch:'
        $script:WorkflowText | Should -Match '(?m)^\s*schedule:'
    }

    It 'restricts permissions to contents: read' {
        $script:WorkflowText | Should -Match '(?m)^permissions:\s*$'
        $script:WorkflowText | Should -Match '(?m)^\s+contents:\s*read'
    }

    It 'defines the unit-tests and license-check jobs' {
        $script:WorkflowText | Should -Match '(?m)^\s{2}unit-tests:'
        $script:WorkflowText | Should -Match '(?m)^\s{2}license-check:'
    }

    It 'orders jobs so license-check depends on unit-tests' {
        $script:WorkflowText | Should -Match '(?m)^\s+needs:\s*unit-tests'
    }

    It 'uses actions/checkout@v4 in every job' {
        ($script:WorkflowLines | Where-Object { $_ -match 'uses:\s*actions/checkout@v4' }).Count |
            Should -Be 2
    }

    It 'runs all script steps with shell: pwsh' {
        ($script:WorkflowLines | Where-Object { $_ -match '^\s*shell:' }) |
            ForEach-Object { $_ | Should -Match 'shell:\s*pwsh' }
    }
}

Describe 'Workflow file references' {
    It 'references the Pester test file and it exists' {
        $script:WorkflowText | Should -Match 'tests/LicenseChecker\.Tests\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'tests/LicenseChecker.Tests.ps1') | Should -BeTrue
    }

    It 'references the checker script and it exists' {
        $script:WorkflowText | Should -Match 'scripts/Invoke-LicenseCheck\.ps1'
        Test-Path (Join-Path $script:RepoRoot 'scripts/Invoke-LicenseCheck.ps1') | Should -BeTrue
    }

    It 'references a config path that exists' {
        $script:WorkflowText | Should -Match 'config/license-config\.json'
        Test-Path (Join-Path $script:RepoRoot 'config/license-config.json') | Should -BeTrue
    }

    It 'references a mock license database that exists' {
        $script:WorkflowText | Should -Match 'fixtures/mock-licenses\.json'
        Test-Path (Join-Path $script:RepoRoot 'fixtures/mock-licenses.json') | Should -BeTrue
    }

    It 'the module the checker script imports exists' {
        Test-Path (Join-Path $script:RepoRoot 'src/LicenseChecker.psm1') | Should -BeTrue
    }
}
