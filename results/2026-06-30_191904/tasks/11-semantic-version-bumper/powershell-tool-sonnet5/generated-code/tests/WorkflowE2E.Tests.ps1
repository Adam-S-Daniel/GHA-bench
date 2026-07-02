# End-to-end acceptance tests for the semantic-version-bumper GitHub Actions
# workflow. Unlike the unit tests, these do NOT call the PowerShell script
# directly -- each test case spins up an isolated temp git repository
# containing a copy of this project plus that case's fixture data, then
# drives the *real* workflow through `act push --rm`. The captured act
# output is what gets asserted against exact expected values (not the
# module functions), so a pass here proves the containerized CI pipeline
# itself performs the correct conventional-commit -> semver bump.
#
# All act output is appended to act-result.txt (in the repo root) with a
# delimiter per test case.
#
# Run with:  Invoke-Pester ./tests/WorkflowE2E.Tests.ps1 -Output Detailed
#
# NOTE: each It block below triggers one real `act push --rm` run (slow --
# 30-90s of Docker execution). There are exactly three cases.

BeforeAll {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $FixturesPath = Join-Path $RepoRoot 'fixtures'
    $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'

    # Start each full test run with a clean act-result.txt; every test case
    # below appends its own clearly delimited section to it.
    Set-Content -Path $ActResultPath -Value "Semantic Version Bumper - act E2E results`n" -NoNewline

    $script:TempRepos = [System.Collections.Generic.List[string]]::new()

    function New-ActTestRepo {
        <#
            Builds an isolated temp git repo containing a copy of this
            project (module, script, workflow, fixtures) with VERSION and
            fixtures/commits.log overwritten for one test case.
        #>
        param(
            [Parameter(Mandatory)] [string]$StartVersion,
            [Parameter(Mandatory)] [string]$CommitLogFixtureName
        )

        $repoDir = Join-Path ([System.IO.Path]::GetTempPath()) "svb-e2e-$(Get-Random)"
        New-Item -ItemType Directory -Path $repoDir | Out-Null

        foreach ($item in @('.actrc', '.github', 'src', 'scripts', 'fixtures', 'tests')) {
            Copy-Item -Path (Join-Path $RepoRoot $item) -Destination (Join-Path $repoDir $item) -Recurse
        }

        Set-Content -Path (Join-Path $repoDir 'VERSION') -Value $StartVersion -NoNewline
        Copy-Item -Path (Join-Path $FixturesPath $CommitLogFixtureName) `
            -Destination (Join-Path $repoDir 'fixtures' 'commits.log') -Force

        Push-Location $repoDir
        try {
            git init -q -b main
            git config user.email 'test-harness@example.com'
            git config user.name 'Act Test Harness'
            git add -A
            git commit -q -m "test case: start=$StartVersion commits=$CommitLogFixtureName"
        } finally {
            Pop-Location
        }

        $script:TempRepos.Add($repoDir)
        return $repoDir
    }

    function Invoke-ActPushTestCase {
        <#
            Runs `act push --rm` inside the given repo dir, appends the
            captured output to act-result.txt under a delimiter, and
            returns an object with the joined output text and exit code.
        #>
        param(
            [Parameter(Mandatory)] [string]$RepoDir,
            [Parameter(Mandatory)] [string]$CaseName
        )

        Push-Location $RepoDir
        try {
            # --pull=false: the ubuntu-latest image is mapped (via .actrc) to
            # the locally-built act-ubuntu-pwsh:latest image, which does not
            # exist in any registry -- act's default force-pull would fail
            # trying to fetch it.
            $rawOutput = & act push --rm --pull=false 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        $joined = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"

        $section = @(
            "===== TEST CASE: $CaseName ====="
            $joined
            "EXIT CODE: $exitCode"
            "===== END TEST CASE: $CaseName ====="
            ''
        ) -join "`n"
        Add-Content -Path $ActResultPath -Value $section

        return [PSCustomObject]@{
            Output   = $joined
            ExitCode = $exitCode
        }
    }
}

AfterAll {
    foreach ($dir in $TempRepos) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'semantic-version-bumper workflow (via act push)' {

    It 'bumps a patch version end-to-end for fix-only commits' {
        $repoDir = New-ActTestRepo -StartVersion '1.0.0' -CommitLogFixtureName 'commits-patch.log'
        $result = Invoke-ActPushTestCase -RepoDir $repoDir -CaseName 'patch-bump'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'RESULT_VERSION=1\.0\.1'
        $result.Output | Should -Match 'RESULT_BUMP_TYPE=Patch'
        $result.Output | Should -Match 'RESULT_OLD_VERSION=1\.0\.0'
        ([regex]::Matches($result.Output, 'Job succeeded')).Count | Should -Be 2
    }

    It 'bumps a minor version end-to-end for a feat commit' {
        $repoDir = New-ActTestRepo -StartVersion '1.0.1' -CommitLogFixtureName 'commits-minor.log'
        $result = Invoke-ActPushTestCase -RepoDir $repoDir -CaseName 'minor-bump'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'RESULT_VERSION=1\.1\.0'
        $result.Output | Should -Match 'RESULT_BUMP_TYPE=Minor'
        $result.Output | Should -Match 'RESULT_OLD_VERSION=1\.0\.1'
        ([regex]::Matches($result.Output, 'Job succeeded')).Count | Should -Be 2
    }

    It 'bumps a major version end-to-end for a breaking-change commit' {
        $repoDir = New-ActTestRepo -StartVersion '1.1.0' -CommitLogFixtureName 'commits-major.log'
        $result = Invoke-ActPushTestCase -RepoDir $repoDir -CaseName 'major-bump'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'RESULT_VERSION=2\.0\.0'
        $result.Output | Should -Match 'RESULT_BUMP_TYPE=Major'
        $result.Output | Should -Match 'RESULT_OLD_VERSION=1\.1\.0'
        ([regex]::Matches($result.Output, 'Job succeeded')).Count | Should -Be 2
    }
}
