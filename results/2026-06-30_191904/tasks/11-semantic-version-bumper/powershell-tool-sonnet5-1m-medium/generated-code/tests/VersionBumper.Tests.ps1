#Requires -Modules Pester

# TDD suite for the semantic version bumper module.
# Each Describe block below was written RED (failing) before the
# corresponding implementation in ../VersionBumper.psm1 was added.

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'VersionBumper.psm1'
    Import-Module $ModulePath -Force

    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vb-tests-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
}

Describe 'Get-CurrentVersion' {

    Context 'Plain VERSION text file' {
        It 'reads a bare semantic version string' {
            $versionFile = Join-Path $script:TempDir 'VERSION'
            Set-Content -Path $versionFile -Value '1.2.3' -NoNewline
            (Get-CurrentVersion -Path $versionFile) | Should -Be '1.2.3'
        }

        It 'trims whitespace and newlines' {
            $versionFile = Join-Path $script:TempDir 'VERSION-ws'
            Set-Content -Path $versionFile -Value "  2.0.1`n`n"
            (Get-CurrentVersion -Path $versionFile) | Should -Be '2.0.1'
        }
    }

    Context 'package.json file' {
        It 'reads the version field from package.json' {
            $pkgFile = Join-Path $script:TempDir 'package.json'
            Set-Content -Path $pkgFile -Value '{"name": "demo", "version": "0.4.5"}'
            (Get-CurrentVersion -Path $pkgFile) | Should -Be '0.4.5'
        }
    }

    Context 'Error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-CurrentVersion -Path (Join-Path $script:TempDir 'missing.json') } | Should -Throw '*not found*'
        }

        It 'throws a meaningful error when package.json has no version field' {
            $pkgFile = Join-Path $script:TempDir 'package-noversion.json'
            Set-Content -Path $pkgFile -Value '{"name": "demo"}'
            { Get-CurrentVersion -Path $pkgFile } | Should -Throw '*version*'
        }

        It 'throws a meaningful error when the version string is not valid semver' {
            $versionFile = Join-Path $script:TempDir 'VERSION-bad'
            Set-Content -Path $versionFile -Value 'not-a-version' -NoNewline
            { Get-CurrentVersion -Path $versionFile } | Should -Throw '*semantic version*'
        }
    }
}

Describe 'Get-CommitBumpType' {

    It 'returns "major" when a commit contains a breaking change marker' {
        $commits = @('feat!: drop support for old API', 'fix: minor cleanup')
        Get-CommitBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns "major" when a commit body contains BREAKING CHANGE:' {
        $commits = @("feat: new api`n`nBREAKING CHANGE: removes old endpoint")
        Get-CommitBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns "minor" when the highest-impact commit is a feat' {
        $commits = @('fix: typo', 'feat: add export command', 'chore: bump deps')
        Get-CommitBumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns "patch" when the highest-impact commit is a fix' {
        $commits = @('chore: bump deps', 'fix: correct off-by-one error')
        Get-CommitBumpType -Commits $commits | Should -Be 'patch'
    }

    It 'returns "none" when there are no conventional commits' {
        $commits = @('chore: bump deps', 'docs: update readme')
        Get-CommitBumpType -Commits $commits | Should -Be 'none'
    }

    It 'throws a meaningful error when commits is empty' {
        { Get-CommitBumpType -Commits @() } | Should -Throw '*commit*'
    }
}

Describe 'Get-NextVersion' {
    It 'bumps the major version and resets minor/patch to zero' {
        Get-NextVersion -Version '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps the minor version and resets patch to zero' {
        Get-NextVersion -Version '1.2.3' -BumpType 'minor' | Should -Be '1.3.0'
    }

    It 'bumps the patch version' {
        Get-NextVersion -Version '1.2.3' -BumpType 'patch' | Should -Be '1.2.4'
    }

    It 'returns the same version unchanged for "none"' {
        Get-NextVersion -Version '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws a meaningful error for an invalid bump type' {
        { Get-NextVersion -Version '1.2.3' -BumpType 'bogus' } | Should -Throw '*bump type*'
    }
}

Describe 'Update-VersionFile' {
    It 'writes the new version to a plain VERSION file' {
        $versionFile = Join-Path $script:TempDir 'VERSION-update'
        Set-Content -Path $versionFile -Value '1.0.0' -NoNewline
        Update-VersionFile -Path $versionFile -NewVersion '1.1.0'
        (Get-Content -Path $versionFile -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'writes the new version into package.json while preserving other fields' {
        $pkgFile = Join-Path $script:TempDir 'package-update.json'
        Set-Content -Path $pkgFile -Value '{"name": "demo", "version": "1.0.0", "private": true}'
        Update-VersionFile -Path $pkgFile -NewVersion '1.1.0'
        $json = Get-Content -Path $pkgFile -Raw | ConvertFrom-Json
        $json.version | Should -Be '1.1.0'
        $json.name | Should -Be 'demo'
        $json.private | Should -Be $true
    }
}

Describe 'New-ChangelogEntry' {
    It 'groups commits under Breaking / Features / Fixes headings' {
        $commits = @(
            'feat: add export command',
            'fix: correct off-by-one error',
            'feat!: drop legacy config format'
        )
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits $commits -Date '2026-07-01'

        $entry | Should -Match '## \[2\.0\.0\] - 2026-07-01'
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match 'drop legacy config format'
        $entry | Should -Match '### Features'
        $entry | Should -Match 'add export command'
        $entry | Should -Match '### Fixes'
        $entry | Should -Match 'correct off-by-one error'
    }

    It 'omits headings for categories with no commits' {
        $commits = @('fix: correct off-by-one error')
        $entry = New-ChangelogEntry -Version '1.0.1' -Commits $commits -Date '2026-07-01'
        $entry | Should -Not -Match '### Features'
        $entry | Should -Not -Match '### Breaking Changes'
        $entry | Should -Match '### Fixes'
    }
}

Describe 'Fixture-driven commit log parsing' {
    It 'parses the feat-only fixture and bumps minor' {
        $log = Get-Content -Path (Join-Path $script:FixturesPath 'commits-feat.txt')
        Get-CommitBumpType -Commits $log | Should -Be 'minor'
    }

    It 'parses the fix-only fixture and bumps patch' {
        $log = Get-Content -Path (Join-Path $script:FixturesPath 'commits-fix.txt')
        Get-CommitBumpType -Commits $log | Should -Be 'patch'
    }

    It 'parses the breaking-change fixture and bumps major' {
        $log = Get-Content -Path (Join-Path $script:FixturesPath 'commits-breaking.txt')
        Get-CommitBumpType -Commits $log | Should -Be 'major'
    }

    It 'parses the mixed fixture and picks the highest-impact bump' {
        $log = Get-Content -Path (Join-Path $script:FixturesPath 'commits-mixed.txt')
        Get-CommitBumpType -Commits $log | Should -Be 'major'
    }
}

Describe 'Invoke-SemanticVersionBump (end-to-end)' {
    It 'bumps VERSION, updates the file, and returns a changelog entry' {
        $versionFile = Join-Path $script:TempDir 'VERSION-e2e'
        $changelogFile = Join-Path $script:TempDir 'CHANGELOG-e2e.md'
        Set-Content -Path $versionFile -Value '1.1.0' -NoNewline
        Set-Content -Path $changelogFile -Value "# Changelog`n"

        $result = Invoke-SemanticVersionBump -VersionFilePath $versionFile -CommitLogPath (Join-Path $script:FixturesPath 'commits-feat.txt') -ChangelogPath $changelogFile

        $result.PreviousVersion | Should -Be '1.1.0'
        $result.NewVersion | Should -Be '1.2.0'
        $result.BumpType | Should -Be 'minor'
        (Get-Content -Path $versionFile -Raw).Trim() | Should -Be '1.2.0'
        (Get-Content -Path $changelogFile -Raw) | Should -Match '1\.2\.0'
    }
}
