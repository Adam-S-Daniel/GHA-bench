#
# Pester tests that validate the GitHub Actions workflow's structure and
# that actionlint passes cleanly, without invoking act (act coverage is
# handled separately by the harness that produces act-result.txt).
#
BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $WorkflowPath = Join-Path $RepoRoot '.github' 'workflows' 'artifact-cleanup-script.yml'
    $RawYaml = Get-Content -LiteralPath $WorkflowPath -Raw

    # PowerShell's ConvertFrom-Yaml is not built in; a minimal hand-rolled
    # parser would be fragile for this well-formed, moderately nested file,
    # so structural checks below use targeted regex assertions against the
    # raw YAML text instead of a full parse.
}

Describe 'Workflow file structure' {
    It 'exists at .github/workflows/artifact-cleanup-script.yml' {
        Test-Path -LiteralPath $WorkflowPath | Should -BeTrue
    }

    It 'declares push, pull_request, schedule, and workflow_dispatch triggers' {
        $RawYaml | Should -Match 'on:'
        $RawYaml | Should -Match 'push:'
        $RawYaml | Should -Match 'pull_request:'
        $RawYaml | Should -Match 'schedule:'
        $RawYaml | Should -Match 'workflow_dispatch:'
    }

    It 'defines the test, dry-run-plan, and apply-cleanup jobs' {
        $RawYaml | Should -Match 'test:'
        $RawYaml | Should -Match 'dry-run-plan:'
        $RawYaml | Should -Match 'apply-cleanup:'
    }

    It 'chains job dependencies with needs:' {
        $RawYaml | Should -Match 'needs:\s*test'
        $RawYaml | Should -Match 'needs:\s*dry-run-plan'
    }

    It 'declares least-privilege permissions' {
        $RawYaml | Should -Match 'permissions:'
        $RawYaml | Should -Match 'contents:\s*read'
    }

    It 'uses actions/checkout@v4 in every job' {
        ($RawYaml | Select-String -Pattern 'uses:\s*actions/checkout@v4' -AllMatches).Matches.Count | Should -Be 3
    }

    It 'uses shell: pwsh for PowerShell run steps' {
        ($RawYaml | Select-String -Pattern 'shell:\s*pwsh' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 3
    }
}

Describe 'Workflow references real files' {
    It 'references the ArtifactCleanup entry script, which exists' {
        $RawYaml | Should -Match 'Invoke-ArtifactCleanup\.ps1'
        Test-Path -LiteralPath (Join-Path $RepoRoot 'Invoke-ArtifactCleanup.ps1') | Should -BeTrue
    }

    It 'references a fixture under fixtures/ that actually exists' {
        # FIXTURE_PATH is intentionally overridable (the act test harness
        # patches it per test case), so resolve whatever value is currently
        # configured rather than assuming a fixed fixture name.
        $RawYaml | Should -Match "FIXTURE_PATH:\s*'\./fixtures/(?<file>[\w.-]+\.json)'"
        $fixtureFile = [regex]::Match($RawYaml, "FIXTURE_PATH:\s*'\./fixtures/(?<file>[\w.-]+\.json)'").Groups['file'].Value
        Test-Path -LiteralPath (Join-Path $RepoRoot 'fixtures' $fixtureFile) | Should -BeTrue
    }

    It 'references the tests directory, which exists and contains Pester specs' {
        $RawYaml | Should -Match '\./tests'
        (Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tests') -Filter '*.Tests.ps1').Count | Should -BeGreaterThan 0
    }
}

Describe 'actionlint validation' {
    It 'passes with exit code 0' {
        $actionlintPath = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlintPath) {
            Set-ItResult -Skipped -Because 'actionlint is not installed in this environment'
            return
        }
        & actionlint $WorkflowPath
        $LASTEXITCODE | Should -Be 0
    }
}
