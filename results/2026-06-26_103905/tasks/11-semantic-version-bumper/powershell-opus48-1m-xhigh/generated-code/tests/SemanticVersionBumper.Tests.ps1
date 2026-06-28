#Requires -Modules Pester

<#
    Pester tests for the Semantic Version Bumper.

    These are written red/green TDD style: each Describe block was added as a
    failing test first, then the minimum implementation in
    SemanticVersionBumper.psm1 was written to make it pass.

    All tests use Pester's $TestDrive sandbox so they never touch real project
    files. Mock commit logs live under ./fixtures and are also reused by the
    `act` integration harness (see Run-ActTests.ps1).
#>

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ directory.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SemanticVersionBumper.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-CurrentVersion' {

    It 'reads a semantic version from a plain VERSION file' {
        $file = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $file -Value '1.2.3' -NoNewline
        Get-CurrentVersion -Path $file | Should -Be '1.2.3'
    }

    It 'ignores comments and blank lines in a plain VERSION file' {
        $file = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $file -Value "# the current release`n`n  2.5.9  "
        Get-CurrentVersion -Path $file | Should -Be '2.5.9'
    }

    It 'reads the version property from a package.json' {
        $file = Join-Path $TestDrive 'package.json'
        Set-Content -Path $file -Value '{ "name": "demo", "version": "0.4.7" }'
        Get-CurrentVersion -Path $file | Should -Be '0.4.7'
    }

    It 'throws a meaningful error when the file does not exist' {
        $missing = Join-Path $TestDrive 'does-not-exist'
        { Get-CurrentVersion -Path $missing } | Should -Throw '*not found*'
    }

    It 'throws when the version is not valid semver' {
        $file = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $file -Value 'not-a-version'
        { Get-CurrentVersion -Path $file } | Should -Throw '*not a valid semantic version*'
    }
}

Describe 'Get-VersionBumpType' {

    It 'returns "patch" for a fix commit' {
        Get-VersionBumpType -Commits @('fix: correct a typo') | Should -Be 'patch'
    }

    It 'returns "minor" for a feat commit' {
        Get-VersionBumpType -Commits @('feat: add login page') | Should -Be 'minor'
    }

    It 'returns "major" for a commit with a "!" breaking marker' {
        Get-VersionBumpType -Commits @('feat!: drop node 14 support') | Should -Be 'major'
    }

    It 'returns "major" for a "feat(scope)!:" breaking marker' {
        Get-VersionBumpType -Commits @('feat(api)!: rename endpoint') | Should -Be 'major'
    }

    It 'returns "major" for a BREAKING CHANGE footer' {
        $commit = "refactor: rework config`n`nBREAKING CHANGE: config file moved"
        Get-VersionBumpType -Commits @($commit) | Should -Be 'major'
    }

    It 'picks the highest precedence across many commits (major > minor > patch)' {
        $commits = @('fix: a', 'feat: b', 'chore: c', 'feat!: d')
        Get-VersionBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns "none" when only non-bumping commits are present' {
        Get-VersionBumpType -Commits @('chore: deps', 'docs: readme', 'style: format') |
            Should -Be 'none'
    }

    It 'returns "none" for an empty commit list' {
        Get-VersionBumpType -Commits @() | Should -Be 'none'
    }
}

Describe 'Get-NextVersion' {

    It 'bumps the patch component' {
        Get-NextVersion -Version '1.2.3' -BumpType 'patch' | Should -Be '1.2.4'
    }

    It 'bumps the minor component and resets patch' {
        Get-NextVersion -Version '1.2.3' -BumpType 'minor' | Should -Be '1.3.0'
    }

    It 'bumps the major component and resets minor and patch' {
        Get-NextVersion -Version '1.2.3' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'returns the same version for "none"' {
        Get-NextVersion -Version '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'drops any pre-release suffix when bumping' {
        Get-NextVersion -Version '1.2.3-beta.1' -BumpType 'patch' | Should -Be '1.2.4'
    }
}

Describe 'Get-CommitsFromFile' {

    It 'reads one commit per line, ignoring blanks' {
        $file = Join-Path $TestDrive 'commits.txt'
        Set-Content -Path $file -Value "feat: a`n`nfix: b`n"
        $commits = Get-CommitsFromFile -Path $file
        $commits | Should -HaveCount 2
        $commits[0] | Should -Be 'feat: a'
        $commits[1] | Should -Be 'fix: b'
    }

    It 'splits multi-line commits on a record separator line "---"' {
        $file = Join-Path $TestDrive 'commits.txt'
        Set-Content -Path $file -Value "feat: a`nBREAKING CHANGE: x`n---`nfix: b"
        $commits = Get-CommitsFromFile -Path $file
        $commits | Should -HaveCount 2
        $commits[0] | Should -BeLike "feat: a*BREAKING CHANGE: x*"
        $commits[1] | Should -Be 'fix: b'
    }

    It 'throws a meaningful error when the file is missing' {
        { Get-CommitsFromFile -Path (Join-Path $TestDrive 'nope.txt') } |
            Should -Throw '*not found*'
    }
}

Describe 'Update-VersionFile' {

    It 'overwrites a plain VERSION file with the new version' {
        $file = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $file -Value '1.0.0' -NoNewline
        Update-VersionFile -Path $file -NewVersion '1.1.0'
        (Get-Content -Path $file -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates only the version field in package.json and keeps other fields' {
        $file = Join-Path $TestDrive 'package.json'
        Set-Content -Path $file -Value '{ "name": "demo", "version": "0.4.7", "private": true }'
        Update-VersionFile -Path $file -NewVersion '0.5.0'
        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
        $json.version | Should -Be '0.5.0'
        $json.name    | Should -Be 'demo'
        $json.private | Should -BeTrue
    }
}

Describe 'New-ChangelogEntry' {

    BeforeAll {
        $script:commits = @(
            'feat: add login page',
            'fix: handle null user',
            'feat(api)!: rename endpoint',
            'chore: bump deps'
        )
        $script:entry = New-ChangelogEntry -Version '2.0.0' -Commits $script:commits -Date '2026-06-27'
    }

    It 'includes a version heading with the date' {
        # NB: use a literal substring check; -BeLike would treat "[2.0.0]" as a
        # wildcard character-class rather than a literal bracketed version.
        $script:entry.Contains('## [2.0.0] - 2026-06-27') | Should -BeTrue
    }

    It 'groups feature commits under a Features heading' {
        $script:entry | Should -BeLike '*### Features*'
        $script:entry | Should -BeLike '*add login page*'
    }

    It 'groups fix commits under a Bug Fixes heading' {
        $script:entry | Should -BeLike '*### Bug Fixes*'
        $script:entry | Should -BeLike '*handle null user*'
    }

    It 'lists breaking changes under a BREAKING CHANGES heading' {
        $script:entry | Should -BeLike '*### BREAKING CHANGES*'
        $script:entry | Should -BeLike '*rename endpoint*'
    }

    It 'omits non-conventional / chore-only sections it does not recognise' {
        # "chore" is not surfaced as its own section in this minimal changelog.
        $script:entry | Should -Not -BeLike '*bump deps*'
    }
}

Describe 'Add-ChangelogEntry' {

    It 'prepends a new entry above existing changelog content but below the title' {
        $file = Join-Path $TestDrive 'CHANGELOG.md'
        $existing = "# Changelog`n`n## [1.0.0] - 2026-01-01`n`n### Features`n- initial`n"
        Set-Content -Path $file -Value $existing
        Add-ChangelogEntry -Path $file -Entry "## [1.1.0] - 2026-06-27`n`n### Features`n- new thing`n"
        $content = Get-Content -Path $file -Raw
        $content | Should -BeLike '*# Changelog*'
        # The new entry must appear before the old one.
        $idxNew = $content.IndexOf('1.1.0')
        $idxOld = $content.IndexOf('1.0.0')
        $idxNew | Should -BeLessThan $idxOld
    }

    It 'creates the changelog with a title when the file does not exist yet' {
        $file = Join-Path $TestDrive 'NEWCHANGELOG.md'
        Add-ChangelogEntry -Path $file -Entry "## [0.1.0] - 2026-06-27`n`n### Features`n- first`n"
        $content = Get-Content -Path $file -Raw
        $content | Should -BeLike '# Changelog*'
        $content | Should -BeLike '*0.1.0*'
    }
}

Describe 'Invoke-VersionBump.ps1 (end-to-end)' {

    BeforeAll {
        $script:Script = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-VersionBump.ps1'
    }

    BeforeEach {
        # Build an isolated mini project inside the test sandbox for each case.
        $script:work = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:work -Force | Out-Null
        $script:versionFile   = Join-Path $script:work 'VERSION'
        $script:commitsFile   = Join-Path $script:work 'commits.txt'
        $script:changelogFile = Join-Path $script:work 'CHANGELOG.md'
    }

    It 'bumps a minor version for a feat commit and writes all outputs' {
        Set-Content -Path $script:versionFile -Value '1.1.0' -NoNewline
        Set-Content -Path $script:commitsFile -Value "feat: add thing`nfix: a bug"

        $out = & $script:Script `
            -VersionFile $script:versionFile `
            -CommitsFile $script:commitsFile `
            -ChangelogFile $script:changelogFile `
            -Date '2026-06-27' *>&1

        $text = ($out | Out-String)
        $text | Should -BeLike '*NEW_VERSION=1.2.0*'
        $text | Should -BeLike '*BUMP_TYPE=minor*'
        (Get-Content $script:versionFile -Raw).Trim() | Should -Be '1.2.0'
        (Get-Content $script:changelogFile -Raw)       | Should -BeLike '*add thing*'
    }

    It 'bumps a major version for a breaking change' {
        Set-Content -Path $script:versionFile -Value '1.5.2' -NoNewline
        Set-Content -Path $script:commitsFile -Value "feat!: rewrite engine"

        $out = & $script:Script `
            -VersionFile $script:versionFile `
            -CommitsFile $script:commitsFile `
            -ChangelogFile $script:changelogFile `
            -Date '2026-06-27' *>&1

        ($out | Out-String) | Should -BeLike '*NEW_VERSION=2.0.0*'
        (Get-Content $script:versionFile -Raw).Trim() | Should -Be '2.0.0'
    }

    It 'leaves the version unchanged when no bumping commits exist' {
        Set-Content -Path $script:versionFile -Value '3.4.5' -NoNewline
        Set-Content -Path $script:commitsFile -Value "chore: tidy`ndocs: update readme"

        $out = & $script:Script `
            -VersionFile $script:versionFile `
            -CommitsFile $script:commitsFile `
            -ChangelogFile $script:changelogFile `
            -Date '2026-06-27' *>&1

        $text = ($out | Out-String)
        $text | Should -BeLike '*NEW_VERSION=3.4.5*'
        $text | Should -BeLike '*BUMP_TYPE=none*'
        (Get-Content $script:versionFile -Raw).Trim() | Should -Be '3.4.5'
    }

    It 'exits non-zero with a clear message when the version file is missing' {
        $out = & $script:Script `
            -VersionFile (Join-Path $script:work 'missing') `
            -CommitsFile $script:commitsFile `
            -ChangelogFile $script:changelogFile *>&1
        $LASTEXITCODE | Should -Be 1
        ($out | Out-String) | Should -BeLike '*not found*'
    }
}
