# Pester tests for the CLI wiring in scripts/Invoke-SemanticVersionBumper.ps1.
#
# These verify argument handling, exit codes, console output, and the
# GITHUB_OUTPUT contract -- i.e. the "plumbing" around Invoke-VersionBump.
# They do NOT assert on conventional-commit-to-semver mapping outcomes
# (feat->minor, fix->patch, breaking->major); that behavioral proof is
# required to run through the real GitHub Actions pipeline via `act` and
# lives in tests/WorkflowE2E.Tests.ps1 instead.
#
# Run with:  Invoke-Pester ./tests/CliScript.Tests.ps1 -Output Detailed

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-SemanticVersionBumper.ps1'
    $FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Invoke-SemanticVersionBumper.ps1 CLI wiring' {

    BeforeEach {
        $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) "cli-$(Get-Random)"
        New-Item -ItemType Directory -Path $workDir | Out-Null
        $script:versionFile = Join-Path $workDir 'VERSION'
        $script:changelogFile = Join-Path $workDir 'CHANGELOG.md'
        $script:githubOutputFile = Join-Path $workDir 'github-output.txt'
        Set-Content -Path $versionFile -Value '1.0.0' -NoNewline
        New-Item -ItemType File -Path $githubOutputFile | Out-Null
    }

    AfterEach {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits 0 and prints the new version on success' {
        $env:GITHUB_OUTPUT = $githubOutputFile
        try {
            $output = & $ScriptPath -VersionFilePath $versionFile `
                -CommitLogPath (Join-Path $FixturesPath 'commits-minor.log') `
                -ChangelogFilePath $changelogFile -Date '2026-06-30' *>&1
            $exitCode = $LASTEXITCODE
        } finally {
            Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match 'New version: 1\.1\.0'
    }

    It 'writes new_version to the GITHUB_OUTPUT file when set' {
        $env:GITHUB_OUTPUT = $githubOutputFile
        try {
            & $ScriptPath -VersionFilePath $versionFile `
                -CommitLogPath (Join-Path $FixturesPath 'commits-minor.log') `
                -ChangelogFilePath $changelogFile -Date '2026-06-30' | Out-Null
        } finally {
            Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }

        Get-Content -Path $githubOutputFile -Raw | Should -Match 'new_version=1\.1\.0'
    }

    It 'exits non-zero with a meaningful error message when the version file is missing' {
        # GitHub Actions' `shell: pwsh` steps prepend
        # `$ErrorActionPreference = 'Stop'` to every run block, so the CLI
        # script must exit(1) cleanly even under that preference rather
        # than relying on the caller's default (Continue). Set it here to
        # reproduce that real-world condition rather than only testing the
        # more forgiving default.
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            $output = & $ScriptPath -VersionFilePath (Join-Path $workDir 'NOPE') `
                -CommitLogPath (Join-Path $FixturesPath 'commits-minor.log') `
                -ChangelogFilePath $changelogFile -Date '2026-06-30' 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }

        $exitCode | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'not found'
    }

    It 'exits non-zero with a meaningful error message when there are no relevant commits' {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            $output = & $ScriptPath -VersionFilePath $versionFile `
                -CommitLogPath (Join-Path $FixturesPath 'commits-none.log') `
                -ChangelogFilePath $changelogFile -Date '2026-06-30' 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }

        $exitCode | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'no version-relevant'
    }
}
