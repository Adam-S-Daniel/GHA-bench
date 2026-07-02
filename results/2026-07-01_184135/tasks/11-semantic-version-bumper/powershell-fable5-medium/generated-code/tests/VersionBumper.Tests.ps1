# Pester tests for the semantic version bumper.
# Built with red/green TDD: each Describe block was written failing first,
# then the minimum implementation was added in src/VersionBumper.psm1.

BeforeAll {
    # Import the module under test fresh for every run.
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'VersionBumper.psm1') -Force
    $script:FixtureDir = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-BumpType' {
    # Conventional-commit rules: breaking -> major, feat -> minor, fix -> patch.
    # The highest-ranked bump across all commits wins.

    It 'returns minor for a feat commit' {
        Get-BumpType -Commits @('feat: add login page') | Should -Be 'minor'
    }

    It 'returns patch for a fix commit' {
        Get-BumpType -Commits @('fix: correct off-by-one error') | Should -Be 'patch'
    }

    It 'returns major when a commit body contains BREAKING CHANGE' {
        $commits = @("feat: rework api`n`nBREAKING CHANGE: endpoints renamed")
        Get-BumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns major for the bang shorthand (feat!:)' {
        Get-BumpType -Commits @('feat!: drop legacy config format') | Should -Be 'major'
    }

    It 'returns the highest bump when commits are mixed' {
        $commits = @(
            'fix: null check',
            'feat: add export button',
            'chore: bump deps'
        )
        Get-BumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns none when no commit is feat/fix/breaking' {
        Get-BumpType -Commits @('chore: tidy', 'docs: update readme') | Should -Be 'none'
    }

    It 'ignores scoped types correctly (fix(parser): ...)' {
        Get-BumpType -Commits @('fix(parser): handle empty input') | Should -Be 'patch'
    }
}

Describe 'Step-Version' {
    # Applies a bump type to a semver string: major resets minor+patch,
    # minor resets patch, none returns the version unchanged.

    It 'bumps major and resets minor/patch' {
        Step-Version -Version '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps minor and resets patch' {
        Step-Version -Version '1.1.0' -BumpType 'minor' | Should -Be '1.2.0'
    }

    It 'bumps patch' {
        Step-Version -Version '2.3.4' -BumpType 'patch' | Should -Be '2.3.5'
    }

    It 'returns the same version for none' {
        Step-Version -Version '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws a meaningful error on an invalid semver string' {
        { Step-Version -Version 'not-a-version' -BumpType 'patch' } |
            Should -Throw '*not a valid semantic version*'
    }
}

Describe 'Get-CurrentVersion / Set-CurrentVersion' {
    # Supports two file formats: a plain version file (raw semver string)
    # and package.json (JSON with a "version" property). Format is chosen
    # by file name.

    BeforeEach {
        $script:TempDir = Join-Path ([IO.Path]::GetTempPath()) ("vb-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }
    AfterEach {
        Remove-Item -Recurse -Force $script:TempDir -ErrorAction SilentlyContinue
    }

    It 'reads a plain version file' {
        $f = Join-Path $TempDir 'version.txt'
        Set-Content -Path $f -Value "1.4.2`n"
        Get-CurrentVersion -Path $f | Should -Be '1.4.2'
    }

    It 'reads the version property from package.json' {
        $f = Join-Path $TempDir 'package.json'
        Set-Content -Path $f -Value '{ "name": "demo", "version": "0.9.1" }'
        Get-CurrentVersion -Path $f | Should -Be '0.9.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $TempDir 'missing.txt') } |
            Should -Throw '*Version file not found*'
    }

    It 'throws a meaningful error when package.json has no version property' {
        $f = Join-Path $TempDir 'package.json'
        Set-Content -Path $f -Value '{ "name": "demo" }'
        { Get-CurrentVersion -Path $f } | Should -Throw '*no "version" property*'
    }

    It 'throws a meaningful error when the version file holds garbage' {
        $f = Join-Path $TempDir 'version.txt'
        Set-Content -Path $f -Value 'banana'
        { Get-CurrentVersion -Path $f } | Should -Throw '*not a valid semantic version*'
    }

    It 'writes a new version back to a plain version file' {
        $f = Join-Path $TempDir 'version.txt'
        Set-Content -Path $f -Value '1.0.0'
        Set-CurrentVersion -Path $f -Version '1.1.0'
        (Get-Content -Path $f -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates only the version property in package.json, keeping other fields' {
        $f = Join-Path $TempDir 'package.json'
        Set-Content -Path $f -Value '{ "name": "demo", "version": "0.9.1", "private": true }'
        Set-CurrentVersion -Path $f -Version '1.0.0'
        $json = Get-Content -Path $f -Raw | ConvertFrom-Json
        $json.version | Should -Be '1.0.0'
        $json.name | Should -Be 'demo'
        $json.private | Should -BeTrue
    }
}

Describe 'New-ChangelogEntry' {
    # Builds a markdown changelog entry grouping commits by category.

    It 'groups commits under Breaking Changes / Features / Fixes headings' {
        $entry = New-ChangelogEntry -Version '2.0.0' -Date '2026-07-01' -Commits @(
            'feat!: drop legacy config',
            'feat: add migration helper',
            'fix: handle empty file',
            'chore: tidy'
        )
        $entry | Should -Match '## \[2\.0\.0\] - 2026-07-01'
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match '- drop legacy config'
        $entry | Should -Match '### Features'
        $entry | Should -Match '- add migration helper'
        $entry | Should -Match '### Fixes'
        $entry | Should -Match '- handle empty file'
        # Non feat/fix/breaking commits do not appear in the changelog.
        $entry | Should -Not -Match 'tidy'
    }

    It 'omits headings with no matching commits' {
        $entry = New-ChangelogEntry -Version '1.0.1' -Date '2026-07-01' -Commits @('fix: patch leak')
        $entry | Should -Not -Match '### Features'
        $entry | Should -Not -Match '### Breaking Changes'
        $entry | Should -Match '### Fixes'
    }
}

Describe 'Invoke-VersionBump (end-to-end)' {
    # Full pipeline: read version file + commit log fixture, bump, rewrite the
    # version file, prepend a changelog entry, return the result object.

    BeforeEach {
        $script:TempDir = Join-Path ([IO.Path]::GetTempPath()) ("vb-e2e-" + [Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }
    AfterEach {
        Remove-Item -Recurse -Force $script:TempDir -ErrorAction SilentlyContinue
    }

    It 'bumps 1.1.0 to 1.2.0 for the feat fixture and writes the changelog' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '1.1.0'
        $cl = Join-Path $TempDir 'CHANGELOG.md'

        $result = Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-feat.txt') `
            -ChangelogPath $cl

        $result.OldVersion | Should -Be '1.1.0'
        $result.NewVersion | Should -Be '1.2.0'
        $result.BumpType | Should -Be 'minor'
        (Get-Content $vf -Raw).Trim() | Should -Be '1.2.0'
        $cl | Should -Exist
        Get-Content $cl -Raw | Should -Match '## \[1\.2\.0\]'
        Get-Content $cl -Raw | Should -Match '- add export button'
    }

    It 'bumps 2.3.4 to 2.3.5 for the fix fixture' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '2.3.4'

        $result = Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-fix.txt') `
            -ChangelogPath (Join-Path $TempDir 'CHANGELOG.md')

        $result.NewVersion | Should -Be '2.3.5'
        $result.BumpType | Should -Be 'patch'
    }

    It 'bumps 1.2.3 to 2.0.0 for the breaking fixture' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '1.2.3'

        $result = Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-breaking.txt') `
            -ChangelogPath (Join-Path $TempDir 'CHANGELOG.md')

        $result.NewVersion | Should -Be '2.0.0'
        $result.BumpType | Should -Be 'major'
    }

    It 'leaves the version untouched and writes no changelog when no bump is needed' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '3.1.4'
        $cl = Join-Path $TempDir 'CHANGELOG.md'

        $result = Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-none.txt') `
            -ChangelogPath $cl

        $result.NewVersion | Should -Be '3.1.4'
        $result.BumpType | Should -Be 'none'
        (Get-Content $vf -Raw).Trim() | Should -Be '3.1.4'
        $cl | Should -Not -Exist
    }

    It 'prepends new entries above existing changelog content' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '1.0.0'
        $cl = Join-Path $TempDir 'CHANGELOG.md'
        Set-Content -Path $cl -Value "# Changelog`n`n## [1.0.0] - 2026-01-01`n`n### Features`n`n- initial release"

        Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-fix.txt') `
            -ChangelogPath $cl | Out-Null

        $content = Get-Content $cl -Raw
        # The new 1.0.1 entry must appear before the old 1.0.0 entry.
        $content.IndexOf('## [1.0.1]') | Should -BeLessThan $content.IndexOf('## [1.0.0]')
        $content | Should -Match '^# Changelog'
    }

    It 'works against a package.json version file' {
        $vf = Join-Path $TempDir 'package.json'
        Set-Content -Path $vf -Value '{ "name": "demo", "version": "0.1.0" }'

        $result = Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $FixtureDir 'commits-feat.txt') `
            -ChangelogPath (Join-Path $TempDir 'CHANGELOG.md')

        $result.NewVersion | Should -Be '0.2.0'
        (Get-Content $vf -Raw | ConvertFrom-Json).version | Should -Be '0.2.0'
    }

    It 'throws a meaningful error when the commit log is missing' {
        $vf = Join-Path $TempDir 'version.txt'
        Set-Content -Path $vf -Value '1.0.0'
        { Invoke-VersionBump -VersionFile $vf `
            -CommitLog (Join-Path $TempDir 'nope.txt') `
            -ChangelogPath (Join-Path $TempDir 'CHANGELOG.md') } |
            Should -Throw '*Commit log file not found*'
    }
}
