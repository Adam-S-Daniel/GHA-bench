<#
.SYNOPSIS
    Structure tests for the GitHub Actions workflow.

.DESCRIPTION
    Verifies the workflow YAML has the expected triggers, jobs, steps, and
    dependencies, that every file it references actually exists in the repo,
    and that actionlint accepts it. The actionlint test auto-skips where the
    tool is unavailable (e.g. inside the act container) and runs everywhere
    else, including the local dev machine and the harness.
#>

BeforeDiscovery {
    # -Skip is evaluated at discovery time, so compute tool presence here.
    $script:NoActionlint = -not (Get-Command actionlint -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'secret-rotation-validator.yml'
    $script:Yaml         = Get-Content -LiteralPath $WorkflowPath -Raw
}

Describe 'Workflow structure' {
    It 'exists at the expected path' {
        Test-Path $WorkflowPath | Should -BeTrue
    }

    It 'declares the expected triggers: push, pull_request, schedule, workflow_dispatch' {
        # The trigger block sits between 'on:' and the next top-level key.
        $onBlock = [regex]::Match($Yaml, '(?ms)^on:\s*\n(.+?)^\S').Groups[1].Value
        $onBlock | Should -Match '(?m)^\s{2}push:'
        $onBlock | Should -Match '(?m)^\s{2}pull_request:'
        $onBlock | Should -Match '(?m)^\s{2}schedule:'
        $onBlock | Should -Match '(?m)^\s{2}workflow_dispatch:'
    }

    It 'restricts permissions to contents: read' {
        $Yaml | Should -Match '(?ms)^permissions:\s*\n\s+contents:\s*read'
    }

    It 'defines a test job and a report job that depends on it' {
        $Yaml | Should -Match '(?m)^\s{2}test:'
        $Yaml | Should -Match '(?m)^\s{2}report:'
        $Yaml | Should -Match '(?m)^\s+needs:\s*test\b'
    }

    It 'checks out the repository with actions/checkout@v4 in every job' {
        ([regex]::Matches($Yaml, [regex]::Escape('uses: actions/checkout@v4'))).Count |
            Should -Be 2
    }

    It 'uses shell: pwsh for every run step (no pwsh -Command from bash)' {
        $runCount   = ([regex]::Matches($Yaml, '(?m)^\s+run:\s*\|')).Count
        $shellCount = ([regex]::Matches($Yaml, '(?m)^\s+shell:\s*pwsh\s*$')).Count
        $runCount | Should -BeGreaterThan 0
        $shellCount | Should -Be $runCount
    }

    It 'references files that actually exist in the repository' {
        # Every repo path the workflow mentions must resolve from the root.
        $Yaml | Should -Match ([regex]::Escape('./Invoke-SecretRotationValidator.ps1'))
        Test-Path (Join-Path $RepoRoot 'Invoke-SecretRotationValidator.ps1') | Should -BeTrue
        $Yaml | Should -Match ([regex]::Escape("Run.Path = './tests'"))
        Test-Path (Join-Path $RepoRoot 'tests') -PathType Container | Should -BeTrue
        $Yaml | Should -Match ([regex]::Escape('fixtures/ci-case.json'))
        Test-Path (Join-Path $RepoRoot 'fixtures' 'ci-case.json') | Should -BeTrue
    }

    It 'pins a deterministic AS_OF_DATE for reproducible CI output' {
        $Yaml | Should -Match "AS_OF_DATE:\s*'2026-01-15'"
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' -Skip:$NoActionlint {
        & actionlint $WorkflowPath 2>&1 | Out-String | Write-Verbose
        $LASTEXITCODE | Should -Be 0
    }
}
