<#
.SYNOPSIS
    Structure tests for .github/workflows/test-results-aggregator.yml.

.DESCRIPTION
    Verifies the workflow YAML has the expected triggers, jobs and steps,
    that every script path the workflow references actually exists, and
    that actionlint passes. The actionlint test is skipped where the tool
    is unavailable (e.g. inside the act container); the act harness runs
    it on the host where it is installed.
#>

BeforeDiscovery {
    $script:HasActionlint = [bool](Get-Command actionlint -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'test-results-aggregator.yml'
    $script:Yaml         = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'Workflow file structure' {
    It 'exists at the expected path' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request and workflow_dispatch triggers' {
        $Yaml | Should -Match '(?m)^on:'
        $Yaml | Should -Match '(?m)^\s+push:'
        $Yaml | Should -Match '(?m)^\s+pull_request:'
        $Yaml | Should -Match '(?m)^\s+workflow_dispatch:'
    }

    It 'restricts permissions to contents: read' {
        $Yaml | Should -Match '(?m)^permissions:\s*$'
        $Yaml | Should -Match '(?m)^\s+contents:\s*read'
    }

    It 'defines the test and aggregate jobs with a dependency between them' {
        $Yaml | Should -Match '(?m)^\s{2}test:'
        $Yaml | Should -Match '(?m)^\s{2}aggregate:'
        $Yaml | Should -Match '(?m)^\s+needs:\s*test'
    }

    It 'uses actions/checkout@v4 and shell: pwsh on run steps' {
        $Yaml | Should -Match 'uses:\s*actions/checkout@v4'
        $Yaml | Should -Match 'shell:\s*pwsh'
        # No bash-wrapped pwsh invocations.
        $Yaml | Should -Not -Match 'pwsh\s+-(Command|File)'
    }

    It 'references the aggregator script by a path that exists' {
        $Yaml | Should -Match ([regex]::Escape('./scripts/Invoke-Aggregator.ps1'))
        Test-Path (Join-Path $RepoRoot 'scripts' 'Invoke-Aggregator.ps1') | Should -BeTrue
    }

    It 'points RESULTS_DIR at an existing fixtures directory' {
        $Yaml | Should -Match '(?m)^\s+RESULTS_DIR:\s*fixtures'
        Test-Path (Join-Path $RepoRoot 'fixtures') | Should -BeTrue
    }

    It 'runs the Pester suite from a tests directory that exists' {
        $Yaml | Should -Match ([regex]::Escape('./tests'))
        Test-Path (Join-Path $RepoRoot 'tests') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' -Skip:(-not $HasActionlint) {
        $output = & actionlint $WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "actionlint reported: $($output -join "`n")"
    }
}
