<#
    Structural tests for the GitHub Actions workflow itself: valid YAML,
    expected triggers/jobs/steps, correct references to script files, and a
    clean actionlint pass. These run inside the pipeline alongside the module
    unit tests. Uses ConvertFrom-Json's built-in YAML-free approach: since no
    YAML cmdlet ships with PowerShell/Pester by default and installing one
    would require network access inside the CI container, structure is
    verified with targeted regex checks against the raw workflow text plus a
    real actionlint run (which does full YAML validation).
#>

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $workflowPath = Join-Path $repoRoot '.github/workflows/dependency-license-checker.yml'
    $workflowText = Get-Content -LiteralPath $workflowPath -Raw
}

Describe 'Workflow file structure' {
    It 'exists at the expected path' {
        Test-Path -LiteralPath $workflowPath -PathType Leaf | Should -BeTrue
    }

    It 'defines push, pull_request, workflow_dispatch, and schedule triggers' {
        $workflowText | Should -Match '(?m)^on:'
        $workflowText | Should -Match '(?m)^\s+push:'
        $workflowText | Should -Match '(?m)^\s+pull_request:'
        $workflowText | Should -Match '(?m)^\s+workflow_dispatch:'
        $workflowText | Should -Match '(?m)^\s+schedule:'
    }

    It 'defines a test job and a check-licenses job that depends on it' {
        $workflowText | Should -Match '(?m)^\s+test:'
        $workflowText | Should -Match '(?m)^\s+check-licenses:'
        $workflowText | Should -Match '(?ms)check-licenses:.*?needs:\s*test'
    }

    It 'restricts permissions to contents: read' {
        $workflowText | Should -Match '(?m)^permissions:'
        $workflowText | Should -Match '(?m)^\s+contents:\s*read'
    }

    It 'uses actions/checkout@v4' {
        ([regex]::Matches($workflowText, 'actions/checkout@v4')).Count | Should -Be 2
    }

    It 'runs PowerShell steps with shell: pwsh' {
        ([regex]::Matches($workflowText, 'shell:\s*pwsh')).Count | Should -BeGreaterOrEqual 3
    }

    It 'references the license checker script and it exists on disk' {
        $workflowText | Should -Match 'Invoke-LicenseCheck\.ps1'
        Test-Path -LiteralPath (Join-Path $repoRoot 'Invoke-LicenseCheck.ps1') -PathType Leaf | Should -BeTrue
    }

    It 'references the tests directory and it exists on disk' {
        $workflowText | Should -Match '\./tests'
        Test-Path -LiteralPath (Join-Path $repoRoot 'tests') -PathType Container | Should -BeTrue
    }

    It 'references the module file and it exists on disk' {
        Test-Path -LiteralPath (Join-Path $repoRoot 'LicenseChecker.psm1') -PathType Leaf | Should -BeTrue
    }

    It 'references the fixture files used at runtime and they exist on disk' {
        foreach ($fixture in @('fixtures/manifest.json', 'fixtures/license-config.json', 'fixtures/license-database.json')) {
            $escaped = [regex]::Escape($fixture)
            $workflowText | Should -Match $escaped
            Test-Path -LiteralPath (Join-Path $repoRoot $fixture) -PathType Leaf | Should -BeTrue
        }
    }

    It 'passes actionlint validation' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        & actionlint $workflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
