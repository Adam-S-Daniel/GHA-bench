# SemanticVersionBumper.Tests.ps1
#
# Pester unit tests for the Semantic Version Bumper module.
#
# These tests drive the design of the module via red/green TDD: each test is
# written FIRST (red), then the minimum module code is added to make it pass
# (green), then refactored. They exercise the pure logic of the bumper in
# isolation (version parsing, bump-type detection, version stepping, changelog
# generation, file updates) so the behaviour is verified independently of the
# GitHub Actions pipeline.

BeforeAll {
    # Import the module under test. $PSScriptRoot points at the directory that
    # contains this test file, so the module path is stable regardless of the
    # caller's working directory.
    $script:ModulePath = Join-Path $PSScriptRoot 'SemanticVersionBumper.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-CurrentVersion' {
    BeforeEach {
        # Each test gets its own throwaway directory so file reads/writes never
        # collide between tests.
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reads a plain version file containing only a semver string' {
        $file = Join-Path $script:WorkDir 'VERSION'
        Set-Content -Path $file -Value '1.4.2'

        Get-CurrentVersion -Path $file | Should -Be '1.4.2'
    }

    It 'tolerates and strips a leading "v" prefix' {
        $file = Join-Path $script:WorkDir 'VERSION'
        Set-Content -Path $file -Value 'v2.0.7'

        Get-CurrentVersion -Path $file | Should -Be '2.0.7'
    }

    It 'reads the version field from a package.json file' {
        $file = Join-Path $script:WorkDir 'package.json'
        Set-Content -Path $file -Value '{ "name": "demo", "version": "3.2.1", "private": true }'

        Get-CurrentVersion -Path $file | Should -Be '3.2.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        $missing = Join-Path $script:WorkDir 'nope.txt'
        { Get-CurrentVersion -Path $missing } | Should -Throw "*not found*"
    }

    It 'throws when the content is not a valid semantic version' {
        $file = Join-Path $script:WorkDir 'VERSION'
        Set-Content -Path $file -Value 'not-a-version'
        { Get-CurrentVersion -Path $file } | Should -Throw "*No semantic version*"
    }

    It 'throws when package.json has no version field' {
        $file = Join-Path $script:WorkDir 'package.json'
        Set-Content -Path $file -Value '{ "name": "demo" }'
        { Get-CurrentVersion -Path $file } | Should -Throw "*does not contain a 'version' field*"
    }
}

Describe 'ConvertFrom-ConventionalCommit' {
    It 'parses a feat commit' {
        $c = ConvertFrom-ConventionalCommit -Message 'feat: add login page'
        $c.Type        | Should -Be 'feat'
        $c.Breaking    | Should -BeFalse
        $c.Description  | Should -Be 'add login page'
        $c.IsConventional | Should -BeTrue
    }

    It 'parses a scoped fix commit' {
        $c = ConvertFrom-ConventionalCommit -Message 'fix(api): handle null response'
        $c.Type        | Should -Be 'fix'
        $c.Scope       | Should -Be 'api'
        $c.Description  | Should -Be 'handle null response'
    }

    It 'flags a breaking change via the "!" marker' {
        $c = ConvertFrom-ConventionalCommit -Message 'feat!: drop node 14 support'
        $c.Type     | Should -Be 'feat'
        $c.Breaking | Should -BeTrue
    }

    It 'flags a breaking change via a "BREAKING CHANGE" token' {
        $c = ConvertFrom-ConventionalCommit -Message 'refactor: rework auth BREAKING CHANGE: tokens changed'
        $c.Breaking | Should -BeTrue
    }

    It 'marks a non-conventional commit as such' {
        $c = ConvertFrom-ConventionalCommit -Message 'just some random message'
        $c.IsConventional | Should -BeFalse
    }
}

Describe 'Get-CommitBumpType' {
    It 'returns "minor" when the highest-priority commit is a feat' {
        Get-CommitBumpType -Commits @('feat: a', 'fix: b', 'chore: c') | Should -Be 'minor'
    }

    It 'returns "patch" when only fixes are present' {
        Get-CommitBumpType -Commits @('fix: a', 'docs: b') | Should -Be 'patch'
    }

    It 'returns "major" when any commit is breaking, even alongside feat/fix' {
        Get-CommitBumpType -Commits @('feat: a', 'fix!: b') | Should -Be 'major'
    }

    It 'returns "none" when no commit warrants a bump' {
        Get-CommitBumpType -Commits @('chore: a', 'docs: b', 'ci: c') | Should -Be 'none'
    }

    It 'returns "none" for an empty commit set' {
        Get-CommitBumpType -Commits @() | Should -Be 'none'
    }
}

Describe 'Get-NextVersion' {
    It 'bumps the patch component' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'patch' | Should -Be '1.2.4'
    }

    It 'bumps the minor component and resets patch' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'minor' | Should -Be '1.3.0'
    }

    It 'bumps the major component and resets minor and patch' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'returns the same version for a "none" bump' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws on a malformed current version' {
        { Get-NextVersion -CurrentVersion 'x.y.z' -BumpType 'patch' } | Should -Throw
    }
}

Describe 'New-ChangelogEntry' {
    It 'renders sections grouped by commit type with a version header and date' {
        $commits = @(
            'feat: add login',
            'fix: correct totals',
            'chore: tidy up'
        )
        $entry = New-ChangelogEntry -Version '1.2.0' -Commits $commits -Date '2026-06-28'

        $entry | Should -Match '## \[1\.2\.0\] - 2026-06-28'
        $entry | Should -Match '### Features'
        $entry | Should -Match '\* add login'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Match '\* correct totals'
    }

    It 'includes a breaking-changes section when present' {
        $commits = @('feat!: drop legacy api')
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits $commits -Date '2026-06-28'

        $entry | Should -Match 'BREAKING CHANGES'
        $entry | Should -Match '\* drop legacy api'
    }
}

Describe 'ConvertFrom-CommitLog' {
    BeforeEach {
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    }
    AfterEach {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reads commit messages one per line and ignores blanks and comments' {
        $log = Join-Path $script:WorkDir 'commits.txt'
        Set-Content -Path $log -Value @(
            '# this is a comment',
            'feat: a',
            '',
            'fix: b'
        )
        $commits = ConvertFrom-CommitLog -Path $log
        $commits.Count | Should -Be 2
        $commits[0] | Should -Be 'feat: a'
        $commits[1] | Should -Be 'fix: b'
    }

    It 'always returns an array, even for a single-commit log' {
        $log = Join-Path $script:WorkDir 'commits.txt'
        Set-Content -Path $log -Value 'fix: only one'
        $commits = ConvertFrom-CommitLog -Path $log
        # @(...) ensures .Count is valid even under Set-StrictMode.
        @($commits).Count | Should -Be 1
        $commits[0] | Should -Be 'fix: only one'
    }
}

Describe 'Set-VersionFile' {
    BeforeEach {
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    }
    AfterEach {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes a plain version file' {
        $file = Join-Path $script:WorkDir 'VERSION'
        Set-Content -Path $file -Value '1.0.0'
        Set-VersionFile -Path $file -Version '1.1.0'
        (Get-Content -Path $file -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates only the version field of a package.json, preserving other fields' {
        $file = Join-Path $script:WorkDir 'package.json'
        Set-Content -Path $file -Value '{ "name": "demo", "version": "1.0.0", "private": true }'
        Set-VersionFile -Path $file -Version '1.1.0'

        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
        $json.version | Should -Be '1.1.0'
        $json.name    | Should -Be 'demo'
        $json.private | Should -BeTrue
    }
}

Describe 'Invoke-VersionBump (orchestrator)' {
    BeforeEach {
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-" + [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    }
    AfterEach {
        Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'bumps a minor version end to end, updating the file and changelog and returning the new version' {
        $versionFile = Join-Path $script:WorkDir 'VERSION'
        $commitLog   = Join-Path $script:WorkDir 'commits.txt'
        $changelog   = Join-Path $script:WorkDir 'CHANGELOG.md'
        Set-Content -Path $versionFile -Value '1.1.0'
        Set-Content -Path $commitLog -Value @('feat: add thing', 'fix: fix thing', 'chore: noise')

        $result = Invoke-VersionBump -VersionFile $versionFile -CommitLog $commitLog -ChangelogFile $changelog -Date '2026-06-28'

        $result.NewVersion      | Should -Be '1.2.0'
        $result.PreviousVersion | Should -Be '1.1.0'
        $result.BumpType        | Should -Be 'minor'

        (Get-Content -Path $versionFile -Raw).Trim() | Should -Be '1.2.0'
        Test-Path $changelog | Should -BeTrue
        (Get-Content -Path $changelog -Raw) | Should -Match '## \[1\.2\.0\] - 2026-06-28'
    }

    It 'computes a major bump when a breaking change is present' {
        $versionFile = Join-Path $script:WorkDir 'VERSION'
        $commitLog   = Join-Path $script:WorkDir 'commits.txt'
        $changelog   = Join-Path $script:WorkDir 'CHANGELOG.md'
        Set-Content -Path $versionFile -Value '0.5.2'
        Set-Content -Path $commitLog -Value @('feat!: remove deprecated api', 'feat: new shiny')

        $result = Invoke-VersionBump -VersionFile $versionFile -CommitLog $commitLog -ChangelogFile $changelog -Date '2026-06-28'
        $result.NewVersion | Should -Be '1.0.0'
        $result.BumpType   | Should -Be 'major'
    }

    It 'handles a single-commit log without error (array-unwrap regression)' {
        $versionFile = Join-Path $script:WorkDir 'VERSION'
        $commitLog   = Join-Path $script:WorkDir 'commits.txt'
        Set-Content -Path $versionFile -Value '1.0.0'
        Set-Content -Path $commitLog -Value 'fix: single line only'

        $result = Invoke-VersionBump -VersionFile $versionFile -CommitLog $commitLog -ChangelogFile (Join-Path $script:WorkDir 'CHANGELOG.md') -Date '2026-06-28'
        $result.NewVersion  | Should -Be '1.0.1'
        $result.BumpType    | Should -Be 'patch'
        $result.CommitCount | Should -Be 1
    }

    It 'throws when there are no commits that warrant a bump' {
        $versionFile = Join-Path $script:WorkDir 'VERSION'
        $commitLog   = Join-Path $script:WorkDir 'commits.txt'
        Set-Content -Path $versionFile -Value '1.0.0'
        Set-Content -Path $commitLog -Value @('chore: noise', 'docs: stuff')

        { Invoke-VersionBump -VersionFile $versionFile -CommitLog $commitLog -ChangelogFile (Join-Path $script:WorkDir 'CHANGELOG.md') -Date '2026-06-28' } |
            Should -Throw "*No version bump*"
    }
}
