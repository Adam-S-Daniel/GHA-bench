# SemanticVersionBumper.Tests.ps1
#
# Pester 5 test suite for the semantic version bumper.
#
# Built red/green/refactor: each `Describe`/`Context` below corresponds to a
# TDD cycle. We wrote the failing assertions first, then the minimum code in
# src/SemanticVersionBumper.ps1 to make them pass.
#
# Run with:  Invoke-Pester -Path tests/SemanticVersionBumper.Tests.ps1

BeforeAll {
    # Dot-source the library under test. The library defines functions only and
    # has no import-time side effects, so it is safe to load into the test scope.
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:Root 'src/SemanticVersionBumper.ps1')
}

Describe 'ConvertTo-SemVer' {
    # --- TDD Cycle 1: parse a semantic version string into its components ---

    It 'parses a plain MAJOR.MINOR.PATCH string' {
        $v = ConvertTo-SemVer '1.2.3'
        $v.Major | Should -Be 1
        $v.Minor | Should -Be 2
        $v.Patch | Should -Be 3
    }

    It 'preserves and strips a leading v prefix' {
        $v = ConvertTo-SemVer 'v2.0.5'
        $v.Major  | Should -Be 2
        $v.Minor  | Should -Be 0
        $v.Patch  | Should -Be 5
        $v.Prefix | Should -Be 'v'
    }

    It 'captures a pre-release identifier' {
        $v = ConvertTo-SemVer '1.0.0-rc.1'
        $v.Prerelease | Should -Be 'rc.1'
    }

    It 'tolerates surrounding whitespace' {
        (ConvertTo-SemVer "  1.4.9 `n").Minor | Should -Be 4
    }

    It 'throws a meaningful error on garbage input' {
        { ConvertTo-SemVer 'not-a-version' } | Should -Throw '*Invalid semantic version*'
    }
}

Describe 'Get-BumpType' {
    # --- TDD Cycle 2: map conventional commit subjects to a bump level ---
    # feat -> minor, fix -> patch, breaking change -> major, anything else -> none.
    # When several commits are present, the highest-precedence bump wins.

    It 'returns minor for a feat commit' {
        Get-BumpType -Commits @('feat: add login page') | Should -Be 'minor'
    }

    It 'returns patch for a fix commit' {
        Get-BumpType -Commits @('fix: correct off-by-one') | Should -Be 'patch'
    }

    It 'honours a scope on the type' {
        Get-BumpType -Commits @('feat(auth): support SSO') | Should -Be 'minor'
    }

    It 'returns major when a commit marks a breaking change with !' {
        Get-BumpType -Commits @('feat!: drop legacy API') | Should -Be 'major'
    }

    It 'returns major when a commit body contains BREAKING CHANGE' {
        Get-BumpType -Commits @('refactor: rework core; BREAKING CHANGE: config moved') | Should -Be 'major'
    }

    It 'returns none for commits that do not affect the version' {
        Get-BumpType -Commits @('chore: tidy up', 'docs: fix typo') | Should -Be 'none'
    }

    It 'picks the highest-precedence bump across many commits' {
        $commits = @('fix: a', 'feat: b', 'chore: c')
        Get-BumpType -Commits $commits | Should -Be 'minor'

        $commits2 = @('fix: a', 'feat!: breaking', 'feat: b')
        Get-BumpType -Commits $commits2 | Should -Be 'major'
    }

    It 'returns none for an empty commit set' {
        Get-BumpType -Commits @() | Should -Be 'none'
    }
}

Describe 'Get-NextVersion' {
    # --- TDD Cycle 3: apply a bump level to a version, resetting lower parts ---

    It 'bumps the major and resets minor/patch' {
        Get-NextVersion -Current '1.4.2' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps the minor and resets patch' {
        Get-NextVersion -Current '1.4.2' -BumpType 'minor' | Should -Be '1.5.0'
    }

    It 'bumps the patch only' {
        Get-NextVersion -Current '1.4.2' -BumpType 'patch' | Should -Be '1.4.3'
    }

    It 'returns the same version when there is nothing to bump' {
        Get-NextVersion -Current '1.4.2' -BumpType 'none' | Should -Be '1.4.2'
    }

    It 'preserves a leading v prefix' {
        Get-NextVersion -Current 'v1.4.2' -BumpType 'minor' | Should -Be 'v1.5.0'
    }

    It 'drops a pre-release identifier when bumping' {
        Get-NextVersion -Current '1.4.2-rc.1' -BumpType 'patch' | Should -Be '1.4.3'
    }
}

Describe 'Get-CurrentVersion' {
    # --- TDD Cycle 4a: read the current version from a file on disk ---

    It 'reads a plain version.txt file' {
        $path = Join-Path $TestDrive 'version.txt'
        Set-Content -Path $path -Value '3.1.4'
        (Get-CurrentVersion -Path $path).Version | Should -Be '3.1.4'
    }

    It 'reads the version field from a package.json file' {
        $path = Join-Path $TestDrive 'package.json'
        '{ "name": "demo", "version": "0.9.2", "private": true }' | Set-Content -Path $path
        $info = Get-CurrentVersion -Path $path
        $info.Version | Should -Be '0.9.2'
        $info.Kind    | Should -Be 'json'
    }

    It 'throws when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $TestDrive 'missing.txt') } |
            Should -Throw '*not found*'
    }

    It 'throws when package.json has no version field' {
        $path = Join-Path $TestDrive 'noversion.json'
        '{ "name": "demo" }' | Set-Content -Path $path
        { Get-CurrentVersion -Path $path } | Should -Throw '*no "version" field*'
    }
}

Describe 'Update-VersionFile' {
    # --- TDD Cycle 4b: write the new version back, preserving file shape ---

    It 'overwrites a plain version.txt with the new value' {
        $path = Join-Path $TestDrive 'v.txt'
        Set-Content -Path $path -Value '1.0.0'
        Update-VersionFile -Path $path -NewVersion '1.1.0'
        (Get-Content -Path $path -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates only the version field in package.json and preserves other keys' {
        $path = Join-Path $TestDrive 'pkg.json'
        @'
{
  "name": "demo",
  "version": "1.0.0",
  "scripts": { "test": "pester" }
}
'@ | Set-Content -Path $path
        Update-VersionFile -Path $path -NewVersion '2.0.0'

        $obj = Get-Content -Path $path -Raw | ConvertFrom-Json
        $obj.version      | Should -Be '2.0.0'
        $obj.name         | Should -Be 'demo'        # untouched
        $obj.scripts.test | Should -Be 'pester'      # nested keys preserved
    }
}

Describe 'New-ChangelogEntry' {
    # --- TDD Cycle 5: render a grouped markdown changelog entry ---

    BeforeAll {
        $script:commits = @(
            'feat(auth): add SSO support',
            'fix: handle null session',
            'feat!: drop legacy v1 endpoints',
            'chore: bump deps'
        )
        $script:entry = New-ChangelogEntry -Version '2.0.0' -Commits $script:commits -Date '2026-06-27'
    }

    It 'includes a version + date heading' {
        $script:entry | Should -Match '## \[2\.0\.0\] - 2026-06-27'
    }

    It 'groups breaking changes under their own section' {
        $script:entry | Should -Match '### .*Breaking'
        $script:entry | Should -Match 'drop legacy v1 endpoints'
    }

    It 'lists features and bug fixes under their sections' {
        $script:entry | Should -Match '### Features'
        $script:entry | Should -Match 'add SSO support'
        $script:entry | Should -Match '### Bug Fixes'
        $script:entry | Should -Match 'handle null session'
    }

    It 'renders the scope alongside the description' {
        $script:entry | Should -Match '\*\*auth\*\*: add SSO support'
    }

    It 'puts uncategorised commits under Other Changes' {
        $script:entry | Should -Match '### Other Changes'
        $script:entry | Should -Match 'bump deps'
    }

    It 'omits empty sections' {
        $entry = New-ChangelogEntry -Version '1.0.1' -Commits @('fix: only a fix') -Date '2026-06-27'
        $entry | Should -Not -Match '### Features'
        $entry | Should -Match '### Bug Fixes'
    }
}

Describe 'Get-CommitMessages' {
    # --- TDD Cycle 6a: read commit subjects from a fixture log file ---

    It 'reads one commit per line and skips blanks and comments' {
        $path = Join-Path $TestDrive 'commits.txt'
        @(
            '# this is a comment',
            'feat: a',
            '',
            'fix: b'
        ) | Set-Content -Path $path

        $msgs = Get-CommitMessages -CommitLogFile $path
        $msgs.Count | Should -Be 2
        $msgs[0]    | Should -Be 'feat: a'
        $msgs[1]    | Should -Be 'fix: b'
    }
}

Describe 'Update-Changelog' {
    # --- TDD Cycle 6b: prepend an entry, keeping the newest on top ---

    It 'creates a changelog with a header when none exists' {
        $path  = Join-Path $TestDrive 'CHANGELOG.md'
        $entry = New-ChangelogEntry -Version '1.0.0' -Commits @('feat: first') -Date '2026-06-27'
        Update-Changelog -Path $path -Entry $entry

        $text = Get-Content -Path $path -Raw
        $text | Should -Match '# Changelog'
        $text | Should -Match '## \[1\.0\.0\]'
    }

    It 'prepends newer entries above older ones' {
        $path = Join-Path $TestDrive 'CHANGELOG2.md'
        Update-Changelog -Path $path -Entry (New-ChangelogEntry -Version '1.0.0' -Commits @('feat: first') -Date '2026-06-27')
        Update-Changelog -Path $path -Entry (New-ChangelogEntry -Version '1.1.0' -Commits @('feat: second') -Date '2026-06-28')

        $text = Get-Content -Path $path -Raw
        # The 1.1.0 heading must appear before the 1.0.0 heading in the file.
        $text.IndexOf('## [1.1.0]') | Should -BeLessThan $text.IndexOf('## [1.0.0]')
    }
}

Describe 'Invoke-VersionBump (end-to-end orchestration)' {
    # --- TDD Cycle 7: tie everything together against real files on disk ---

    BeforeEach {
        # Fresh sandbox per test so writes don't leak between cases.
        $script:work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:work | Out-Null
    }

    It 'bumps a minor release end-to-end and writes all artifacts' {
        Set-Content -Path (Join-Path $work 'version.txt') -Value '1.1.0'
        Set-Content -Path (Join-Path $work 'commits.txt')  -Value @('feat: shiny new thing', 'chore: noise')

        $result = Invoke-VersionBump `
            -VersionFile   (Join-Path $work 'version.txt') `
            -CommitLogFile (Join-Path $work 'commits.txt') `
            -ChangelogFile (Join-Path $work 'CHANGELOG.md') `
            -Date '2026-06-27'

        $result.PreviousVersion | Should -Be '1.1.0'
        $result.BumpType        | Should -Be 'minor'
        $result.NewVersion      | Should -Be '1.2.0'

        # version file updated on disk
        (Get-Content (Join-Path $work 'version.txt') -Raw).Trim() | Should -Be '1.2.0'
        # changelog created with the new entry
        (Get-Content (Join-Path $work 'CHANGELOG.md') -Raw) | Should -Match '## \[1\.2\.0\] - 2026-06-27'
    }

    It 'bumps a major release when a commit is breaking (package.json)' {
        '{ "name": "demo", "version": "2.3.4" }' | Set-Content -Path (Join-Path $work 'package.json')
        Set-Content -Path (Join-Path $work 'commits.txt') -Value @('feat!: incompatible change')

        $result = Invoke-VersionBump `
            -VersionFile   (Join-Path $work 'package.json') `
            -CommitLogFile (Join-Path $work 'commits.txt') `
            -ChangelogFile (Join-Path $work 'CHANGELOG.md') `
            -Date '2026-06-27'

        $result.NewVersion | Should -Be '3.0.0'
        ((Get-Content (Join-Path $work 'package.json') -Raw | ConvertFrom-Json).version) | Should -Be '3.0.0'
    }

    It 'auto-detects version.txt when no version file is specified' {
        Set-Content -Path (Join-Path $work 'version.txt') -Value '0.4.0'
        Set-Content -Path (Join-Path $work 'commits.txt')  -Value @('fix: patch it')

        $result = Invoke-VersionBump -RepositoryPath $work `
            -CommitLogFile (Join-Path $work 'commits.txt') `
            -ChangelogFile (Join-Path $work 'CHANGELOG.md') `
            -Date '2026-06-27'

        $result.NewVersion | Should -Be '0.4.1'
    }

    It 'makes no change and reports none when no commits bump the version' {
        Set-Content -Path (Join-Path $work 'version.txt') -Value '5.0.0'
        Set-Content -Path (Join-Path $work 'commits.txt')  -Value @('docs: tweak readme', 'chore: deps')

        $result = Invoke-VersionBump `
            -VersionFile   (Join-Path $work 'version.txt') `
            -CommitLogFile (Join-Path $work 'commits.txt') `
            -ChangelogFile (Join-Path $work 'CHANGELOG.md') `
            -Date '2026-06-27'

        $result.BumpType   | Should -Be 'none'
        $result.NewVersion | Should -Be '5.0.0'
        (Get-Content (Join-Path $work 'version.txt') -Raw).Trim() | Should -Be '5.0.0'
    }

    It 'throws a clear error when the version file is missing' {
        Set-Content -Path (Join-Path $work 'commits.txt') -Value @('feat: x')
        { Invoke-VersionBump -VersionFile (Join-Path $work 'nope.txt') -CommitLogFile (Join-Path $work 'commits.txt') } |
            Should -Throw '*not found*'
    }
}
