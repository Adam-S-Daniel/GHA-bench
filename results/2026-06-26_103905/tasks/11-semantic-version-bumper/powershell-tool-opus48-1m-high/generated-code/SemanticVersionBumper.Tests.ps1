# SemanticVersionBumper.Tests.ps1
#
# Pester v5 test suite for the semantic version bumper.
#
# These tests were written test-first (red/green TDD). Each Describe block
# corresponds to one unit of functionality in SemanticVersionBumper.ps1.
# The implementation file is dot-sourced in BeforeAll so the functions under
# test are available in the test scope.

BeforeAll {
    # Dot-source the script under test. $PSCommandPath points at this test file,
    # so we resolve the implementation that lives alongside it.
    . (Join-Path $PSScriptRoot 'SemanticVersionBumper.ps1')

    # TestDrive is a Pester-provided temporary path that is cleaned up
    # automatically after the run; we use it for fixture files.
}

Describe 'Get-SemanticVersion' {

    Context 'parsing a plain version file' {
        It 'parses a bare semver string "1.2.3"' {
            $file = Join-Path $TestDrive 'version.txt'
            Set-Content -Path $file -Value '1.2.3'

            $v = Get-SemanticVersion -Path $file

            $v.Major | Should -Be 1
            $v.Minor | Should -Be 2
            $v.Patch | Should -Be 3
        }

        It 'tolerates a leading "v" prefix and surrounding whitespace' {
            $file = Join-Path $TestDrive 'version2.txt'
            Set-Content -Path $file -Value "  v10.0.5  `n"

            $v = Get-SemanticVersion -Path $file

            $v.Major | Should -Be 10
            $v.Minor | Should -Be 0
            $v.Patch | Should -Be 5
        }
    }

    Context 'parsing a package.json file' {
        It 'extracts the version from package.json' {
            $file = Join-Path $TestDrive 'package.json'
            @'
{
  "name": "demo",
  "version": "2.3.4",
  "scripts": { "test": "pester" }
}
'@ | Set-Content -Path $file

            $v = Get-SemanticVersion -Path $file

            $v.Major | Should -Be 2
            $v.Minor | Should -Be 3
            $v.Patch | Should -Be 4
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-SemanticVersion -Path (Join-Path $TestDrive 'nope.txt') } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error when no valid version is present' {
            $file = Join-Path $TestDrive 'garbage.txt'
            Set-Content -Path $file -Value 'this has no version'

            { Get-SemanticVersion -Path $file } |
                Should -Throw -ExpectedMessage '*No valid semantic version*'
        }
    }
}

Describe 'Get-CommitBumpType' {

    It 'returns "patch" for a fix commit' {
        Get-CommitBumpType -Commits @('fix: correct null pointer') | Should -Be 'patch'
    }

    It 'returns "minor" for a feat commit' {
        Get-CommitBumpType -Commits @('feat: add login page') | Should -Be 'minor'
    }

    It 'returns "major" for a commit with a "!" breaking marker' {
        Get-CommitBumpType -Commits @('feat!: drop node 14 support') | Should -Be 'major'
    }

    It 'returns "major" for a commit body containing BREAKING CHANGE' {
        Get-CommitBumpType -Commits @('refactor: rework api', 'BREAKING CHANGE: removed old endpoint') |
            Should -Be 'major'
    }

    It 'honours scopes such as feat(api): ...' {
        Get-CommitBumpType -Commits @('feat(api): new field') | Should -Be 'minor'
    }

    It 'returns the highest precedence across mixed commits' {
        $commits = @('fix: a', 'feat: b', 'chore: c')
        Get-CommitBumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns "none" when there are no bump-worthy commits' {
        Get-CommitBumpType -Commits @('chore: tidy', 'docs: readme') | Should -Be 'none'
    }

    It 'reads commits from a fixture file via -Path' {
        $file = Join-Path $TestDrive 'commits.txt'
        Set-Content -Path $file -Value @('chore: stuff', 'fix: bug')
        Get-CommitBumpType -Path $file | Should -Be 'patch'
    }
}

Describe 'Get-NextVersion' {

    BeforeAll {
        $base = Get-SemanticVersion -InputString '1.4.2'
    }

    It 'bumps the patch component' {
        (Get-NextVersion -Version $base -BumpType 'patch').ToString() | Should -Be '1.4.3'
    }

    It 'bumps the minor component and resets patch' {
        (Get-NextVersion -Version $base -BumpType 'minor').ToString() | Should -Be '1.5.0'
    }

    It 'bumps the major component and resets minor and patch' {
        (Get-NextVersion -Version $base -BumpType 'major').ToString() | Should -Be '2.0.0'
    }

    It 'leaves the version unchanged for "none"' {
        (Get-NextVersion -Version $base -BumpType 'none').ToString() | Should -Be '1.4.2'
    }
}

Describe 'New-ChangelogEntry' {

    It 'groups commits into Features / Bug Fixes / Breaking sections' {
        $commits = @(
            'feat: add search',
            'fix: handle empty input',
            'feat!: change config format'
        )
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits $commits -Date '2026-06-27'

        # Note: -Match uses regex; brackets are escaped. (-BeLike would treat
        # "[2.0.0]" as a character class, hence regex here.)
        $entry | Should -Match '## \[2\.0\.0\] - 2026-06-27'
        $entry | Should -BeLike '*### Features*'
        $entry | Should -BeLike '*add search*'
        $entry | Should -BeLike '*### Bug Fixes*'
        $entry | Should -BeLike '*handle empty input*'
        $entry | Should -BeLike '*### BREAKING CHANGES*'
        $entry | Should -BeLike '*change config format*'
    }

    It 'omits empty sections' {
        $entry = New-ChangelogEntry -Version '1.0.1' -Commits @('fix: a bug') -Date '2026-06-27'
        $entry | Should -BeLike '*### Bug Fixes*'
        $entry | Should -Not -BeLike '*### Features*'
    }
}

Describe 'Set-SemanticVersion' {

    It 'writes the new version back to a plain version file' {
        $file = Join-Path $TestDrive 'wv.txt'
        Set-Content -Path $file -Value '1.0.0'

        Set-SemanticVersion -Path $file -NewVersion '1.1.0'

        (Get-Content -Path $file -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates the version field in package.json while preserving other fields' {
        $file = Join-Path $TestDrive 'pkg.json'
        @'
{
  "name": "demo",
  "version": "1.0.0",
  "license": "MIT"
}
'@ | Set-Content -Path $file

        Set-SemanticVersion -Path $file -NewVersion '1.1.0'

        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
        $json.version | Should -Be '1.1.0'
        $json.name    | Should -Be 'demo'
        $json.license | Should -Be 'MIT'
    }
}

Describe 'Invoke-VersionBump (integration)' {

    It 'bumps version.txt with a feat commit and writes the changelog' {
        $verFile = Join-Path $TestDrive 'iv-version.txt'
        $logFile = Join-Path $TestDrive 'iv-commits.txt'
        $chgFile = Join-Path $TestDrive 'iv-CHANGELOG.md'
        Set-Content -Path $verFile -Value '1.1.0'
        Set-Content -Path $logFile -Value @('feat: shiny new thing', 'fix: small bug')

        $result = Invoke-VersionBump -VersionFile $verFile -CommitLogFile $logFile -ChangelogFile $chgFile -Date '2026-06-27'

        $result.NewVersion | Should -Be '1.2.0'
        $result.BumpType   | Should -Be 'minor'
        (Get-Content -Path $verFile -Raw).Trim() | Should -Be '1.2.0'
        (Get-Content -Path $chgFile -Raw) | Should -Match '## \[1\.2\.0\]'
        (Get-Content -Path $chgFile -Raw) | Should -BeLike '*shiny new thing*'
    }

    It 'performs a major bump on a breaking change in package.json' {
        $verFile = Join-Path $TestDrive 'iv-package.json'
        $logFile = Join-Path $TestDrive 'iv-commits2.txt'
        $chgFile = Join-Path $TestDrive 'iv-CHANGELOG2.md'
        @'
{ "name": "demo", "version": "2.3.4" }
'@ | Set-Content -Path $verFile
        Set-Content -Path $logFile -Value @('feat!: overhaul the engine')

        $result = Invoke-VersionBump -VersionFile $verFile -CommitLogFile $logFile -ChangelogFile $chgFile -Date '2026-06-27'

        $result.NewVersion | Should -Be '3.0.0'
        $result.BumpType   | Should -Be 'major'
        (Get-Content -Path $verFile -Raw | ConvertFrom-Json).version | Should -Be '3.0.0'
    }

    It 'throws when the commit log yields no bump-worthy commits' {
        $verFile = Join-Path $TestDrive 'iv-version3.txt'
        $logFile = Join-Path $TestDrive 'iv-commits3.txt'
        $chgFile = Join-Path $TestDrive 'iv-CHANGELOG3.md'
        Set-Content -Path $verFile -Value '1.0.0'
        Set-Content -Path $logFile -Value @('chore: nothing', 'docs: stuff')

        { Invoke-VersionBump -VersionFile $verFile -CommitLogFile $logFile -ChangelogFile $chgFile -FailOnNoBump } |
            Should -Throw -ExpectedMessage '*no version bump*'
    }
}
