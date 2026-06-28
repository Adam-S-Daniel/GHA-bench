#Requires -Modules Pester

<#
    Integration tests for the Update-SemanticVersion.ps1 orchestrator.

    These drive the whole script (read version -> classify commits -> compute next
    version -> write files -> emit output) against fixture data in an isolated
    TestDrive directory. They were written red/green alongside the script.

    The end-to-end behaviour is *also* exercised through the real GitHub Actions
    pipeline in Tests/Workflow.Tests.ps1 (the "all tests run through act"
    requirement); these script-level tests give fast TDD feedback during build.

    Parameters are passed via hashtable splatting (not array splatting) because
    array splatting binds elements positionally and ignores -Name tokens.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Update-SemanticVersion.ps1'

    # Helper: run the orchestrator with named parameters and capture stdout/exit.
    function Invoke-Bumper {
        param([hashtable]$Params)
        $out = & $script:ScriptPath @Params 2>&1
        [pscustomobject]@{
            Output = @($out | ForEach-Object { $_.ToString() })
            Exit   = $LASTEXITCODE
        }
    }

    # Helper: create an isolated working directory under TestDrive.
    function New-WorkDir {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        return $dir
    }

    # Helper: write a delimited mock commit log.
    function New-CommitLog {
        param([string]$Path, [string[]]$Messages)
        $blocks = $Messages | ForEach-Object { "<<<COMMIT>>>`n$_" }
        Set-Content -Path $Path -Value ($blocks -join "`n") -Encoding utf8
    }
}

Describe 'Update-SemanticVersion.ps1 (orchestrator)' {

    It 'bumps a minor version from a feat commit and updates the VERSION file' {
        $dir = New-WorkDir
        $vf  = Join-Path $dir 'VERSION'
        $log = Join-Path $dir 'commits.txt'
        $cl  = Join-Path $dir 'CHANGELOG.md'
        Set-Content -Path $vf -Value '1.1.0' -Encoding utf8
        New-CommitLog -Path $log -Messages @('feat: add thing', 'docs: tidy')

        $r = Invoke-Bumper @{ VersionFile = $vf; CommitLogPath = $log; ChangelogFile = $cl; Date = '2026-06-28' }

        $r.Exit | Should -Be 0
        $r.Output | Should -Contain 'NEW_VERSION=1.2.0'
        $r.Output | Should -Contain 'BUMP_TYPE=minor'
        (Get-Content -Path $vf -Raw).Trim() | Should -Be '1.2.0'
        (Get-Content -Path $cl -Raw) | Should -Match ([regex]::Escape('## [1.2.0] - 2026-06-28'))
    }

    It 'bumps a major version from a breaking commit in a package.json' {
        $dir = New-WorkDir
        $pkg = Join-Path $dir 'package.json'
        $log = Join-Path $dir 'commits.txt'
        '{ "name": "demo", "version": "2.5.1" }' | Set-Content -Path $pkg -Encoding utf8
        New-CommitLog -Path $log -Messages @("feat!: overhaul`n`nBREAKING CHANGE: removed api")

        $r = Invoke-Bumper @{ VersionFile = $pkg; CommitLogPath = $log; ChangelogFile = (Join-Path $dir 'CHANGELOG.md'); Date = '2026-06-28' }

        $r.Exit | Should -Be 0
        $r.Output | Should -Contain 'NEW_VERSION=3.0.0'
        $r.Output | Should -Contain 'BUMP_TYPE=major'
        ((Get-Content -Path $pkg -Raw | ConvertFrom-Json).version) | Should -Be '3.0.0'
    }

    It 'does not change the version when there are no bumping commits' {
        $dir = New-WorkDir
        $vf  = Join-Path $dir 'VERSION'
        $log = Join-Path $dir 'commits.txt'
        Set-Content -Path $vf -Value '3.2.1' -Encoding utf8
        New-CommitLog -Path $log -Messages @('docs: a', 'chore: b')

        $r = Invoke-Bumper @{ VersionFile = $vf; CommitLogPath = $log; ChangelogFile = (Join-Path $dir 'CHANGELOG.md') }

        $r.Exit | Should -Be 0
        $r.Output | Should -Contain 'NEW_VERSION=3.2.1'
        $r.Output | Should -Contain 'BUMP_TYPE=none'
        (Get-Content -Path $vf -Raw).Trim() | Should -Be '3.2.1'
    }

    It 'honours -DryRun by leaving files untouched while still reporting the version' {
        $dir = New-WorkDir
        $vf  = Join-Path $dir 'VERSION'
        $log = Join-Path $dir 'commits.txt'
        Set-Content -Path $vf -Value '1.0.0' -Encoding utf8
        New-CommitLog -Path $log -Messages @('fix: patch it')

        $r = Invoke-Bumper @{ VersionFile = $vf; CommitLogPath = $log; ChangelogFile = (Join-Path $dir 'CHANGELOG.md'); DryRun = $true }

        $r.Exit | Should -Be 0
        $r.Output | Should -Contain 'NEW_VERSION=1.0.1'
        (Get-Content -Path $vf -Raw).Trim() | Should -Be '1.0.0'   # unchanged
    }

    It 'writes step outputs to the GITHUB_OUTPUT file when set' {
        $dir = New-WorkDir
        $vf  = Join-Path $dir 'VERSION'
        $log = Join-Path $dir 'commits.txt'
        $gho = Join-Path $dir 'gh_output.txt'
        Set-Content -Path $vf -Value '1.1.0' -Encoding utf8
        Set-Content -Path $gho -Value '' -Encoding utf8   # GITHUB_OUTPUT must exist
        New-CommitLog -Path $log -Messages @('feat: x')

        # Save/restore any pre-existing value (this test also runs inside act,
        # where GITHUB_OUTPUT is already set by the runner).
        $prev = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_OUTPUT = $gho
            $r = Invoke-Bumper @{ VersionFile = $vf; CommitLogPath = $log; ChangelogFile = (Join-Path $dir 'CHANGELOG.md') }
        } finally {
            if ($null -eq $prev) { Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue }
            else { $env:GITHUB_OUTPUT = $prev }
        }

        $r.Exit | Should -Be 0
        $ghoContent = Get-Content -Path $gho -Raw
        $ghoContent | Should -Match 'new_version=1\.2\.0'
        $ghoContent | Should -Match 'bump_type=minor'
    }

    It 'exits non-zero with a meaningful error when the version file is missing' {
        $dir = New-WorkDir
        $log = Join-Path $dir 'commits.txt'
        New-CommitLog -Path $log -Messages @('feat: x')

        $r = Invoke-Bumper @{ VersionFile = (Join-Path $dir 'NOPE'); CommitLogPath = $log }

        $r.Exit | Should -Not -Be 0
        ($r.Output -join "`n") | Should -Match 'Version file not found'
    }
}
