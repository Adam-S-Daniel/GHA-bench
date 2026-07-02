# Pester tests for the semantic version bumper.
# TDD: these tests are written first and drive the implementation in
# scripts/VersionBumper.psm1. Run with: Invoke-Pester -Path ./tests

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force

    $script:FixturesPath = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Get-CurrentVersion' {
    It 'reads a version from a plain VERSION file' {
        $path = Join-Path $script:FixturesPath 'VERSION-simple'
        Get-CurrentVersion -Path $path | Should -Be '1.2.3'
    }

    It 'reads a version from a package.json file' {
        $path = Join-Path $script:FixturesPath 'package-simple.json'
        Get-CurrentVersion -Path $path | Should -Be '2.0.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $script:FixturesPath 'does-not-exist.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error when no version can be parsed' {
        $path = Join-Path $script:FixturesPath 'VERSION-invalid'
        { Get-CurrentVersion -Path $path } | Should -Throw -ExpectedMessage '*Unable to parse*'
    }
}

Describe 'Get-VersionBumpType' {
    It 'returns "major" when a commit contains a breaking change marker' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-breaking.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'major'
    }

    It 'returns "major" when a commit subject has a "!" breaking indicator' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-breaking-bang.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'major'
    }

    It 'returns "minor" when the highest-impact commit is a feat' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-feat.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'minor'
    }

    It 'returns "patch" when the highest-impact commit is a fix' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-fix.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'patch'
    }

    It 'returns "none" when there are no conventional commit prefixes' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-none.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'none'
    }

    It 'prioritizes major over minor and patch when commits are mixed' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-mixed.log')
        Get-VersionBumpType -CommitMessages $commits | Should -Be 'major'
    }
}

Describe 'Get-NextVersion' {
    It 'bumps the major version and resets minor/patch to 0' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps the minor version and resets patch to 0' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'minor' | Should -Be '1.3.0'
    }

    It 'bumps the patch version' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'patch' | Should -Be '1.2.4'
    }

    It 'returns the same version when there is nothing to bump' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws a meaningful error for a malformed current version' {
        { Get-NextVersion -CurrentVersion 'not-a-version' -BumpType 'patch' } |
            Should -Throw -ExpectedMessage '*Invalid semantic version*'
    }
}

Describe 'Update-VersionFile' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'updates a plain VERSION file in place' {
        $path = Join-Path $script:TempDir 'VERSION'
        Set-Content -Path $path -Value '1.2.3' -NoNewline
        Update-VersionFile -Path $path -NewVersion '1.3.0'
        (Get-Content -Path $path -Raw).Trim() | Should -Be '1.3.0'
    }

    It 'updates the version field inside a package.json file, preserving other fields' {
        $path = Join-Path $script:TempDir 'package.json'
        $original = Get-Content (Join-Path $script:FixturesPath 'package-simple.json') -Raw
        Set-Content -Path $path -Value $original -NoNewline
        Update-VersionFile -Path $path -NewVersion '2.1.0'

        $updated = Get-Content -Path $path -Raw | ConvertFrom-Json
        $updated.version | Should -Be '2.1.0'
        $updated.name | Should -Be 'sample-package'
    }
}

Describe 'New-ChangelogEntry' {
    It 'formats commit messages into grouped changelog markdown' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-mixed.log')
        $entry = New-ChangelogEntry -Version '2.0.0' -CommitMessages $commits

        $entry | Should -Match '## 2\.0\.0'
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match '### Features'
        $entry | Should -Match '### Fixes'
    }
}

Describe 'Invoke-VersionBump (end-to-end)' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
        $script:VersionPath = Join-Path $script:TempDir 'VERSION'
        $script:ChangelogPath = Join-Path $script:TempDir 'CHANGELOG.md'
        Set-Content -Path $script:VersionPath -Value '1.0.0' -NoNewline
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'bumps minor version for a feat commit log and writes a changelog' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-feat.log')
        $result = Invoke-VersionBump -VersionFilePath $script:VersionPath -ChangelogPath $script:ChangelogPath -CommitMessages $commits

        $result.NewVersion | Should -Be '1.1.0'
        (Get-Content -Path $script:VersionPath -Raw).Trim() | Should -Be '1.1.0'
        Get-Content -Path $script:ChangelogPath -Raw | Should -Match '## 1\.1\.0'
    }

    It 'bumps major version for a breaking commit log' {
        $commits = Get-Content (Join-Path $script:FixturesPath 'commits-breaking.log')
        $result = Invoke-VersionBump -VersionFilePath $script:VersionPath -ChangelogPath $script:ChangelogPath -CommitMessages $commits

        $result.NewVersion | Should -Be '2.0.0'
    }
}
