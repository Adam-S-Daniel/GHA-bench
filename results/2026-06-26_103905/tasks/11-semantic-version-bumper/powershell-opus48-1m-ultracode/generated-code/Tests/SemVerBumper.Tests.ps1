#Requires -Modules Pester

<#
    Unit tests for the SemVerBumper module.

    These tests follow red/green TDD: each `Describe`/`It` was written before the
    corresponding function existed, observed failing, then made to pass with the
    minimum implementation in SemVerBumper.psm1.

    The tests exercise the pure building blocks (version parsing, bump-type
    detection, next-version computation, changelog generation, file mutation).
    End-to-end behaviour is validated separately through the GitHub Actions
    pipeline (see Tests/Workflow.Tests.ps1), per the task's "all tests run
    through act" requirement.
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'SemVerBumper.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertTo-SemVerObject' {
    It 'parses a plain MAJOR.MINOR.PATCH string' {
        $v = ConvertTo-SemVerObject -Version '1.2.3'
        $v.Major | Should -Be 1
        $v.Minor | Should -Be 2
        $v.Patch | Should -Be 3
    }

    It 'parses a version with a prerelease and build metadata' {
        $v = ConvertTo-SemVerObject -Version '2.0.0-rc.1+build.5'
        $v.Major      | Should -Be 2
        $v.Minor      | Should -Be 0
        $v.Patch      | Should -Be 0
        $v.Prerelease | Should -Be 'rc.1'
        $v.Build      | Should -Be 'build.5'
    }

    It 'throws a meaningful error on a non-semver string' {
        { ConvertTo-SemVerObject -Version 'not.a.version' } |
            Should -Throw -ExpectedMessage '*not a valid semantic version*'
    }
}

Describe 'Get-CommitBumpType' {
    It 'classifies a feat commit as minor' {
        Get-CommitBumpType -Message 'feat: add login page' | Should -Be 'minor'
    }

    It 'classifies a fix commit as patch' {
        Get-CommitBumpType -Message 'fix: handle null user' | Should -Be 'patch'
    }

    It 'honours a scope on the type' {
        Get-CommitBumpType -Message 'feat(auth): add SSO' | Should -Be 'minor'
    }

    It 'treats a trailing ! after the type as a breaking change (major)' {
        Get-CommitBumpType -Message 'feat!: drop node 14' | Should -Be 'major'
    }

    It 'treats ! after a scope as a breaking change (major)' {
        Get-CommitBumpType -Message 'refactor(api)!: rename endpoints' | Should -Be 'major'
    }

    It 'detects a BREAKING CHANGE footer in the body (major)' {
        $msg = "feat: new config format`n`nBREAKING CHANGE: config keys renamed"
        Get-CommitBumpType -Message $msg | Should -Be 'major'
    }

    It 'detects the hyphenated BREAKING-CHANGE token (major)' {
        $msg = "fix: tweak`n`nBREAKING-CHANGE: removed flag"
        Get-CommitBumpType -Message $msg | Should -Be 'major'
    }

    It 'returns none for non-bumping types like docs/chore' {
        Get-CommitBumpType -Message 'docs: update readme' | Should -Be 'none'
        Get-CommitBumpType -Message 'chore: bump deps'    | Should -Be 'none'
    }

    It 'returns none for a non-conventional commit subject' {
        Get-CommitBumpType -Message 'just some random commit' | Should -Be 'none'
    }

    It 'is case-insensitive on the commit type' {
        Get-CommitBumpType -Message 'FEAT: shout' | Should -Be 'minor'
    }
}

Describe 'Get-VersionBumpType' {
    It 'returns none for an empty commit set' {
        Get-VersionBumpType -Commits @() | Should -Be 'none'
    }

    It 'picks the highest precedence (major beats minor beats patch)' {
        $commits = @('fix: a', 'feat: b', 'feat!: c')
        Get-VersionBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns minor when feat present without breaking' {
        Get-VersionBumpType -Commits @('fix: a', 'feat: b', 'docs: c') | Should -Be 'minor'
    }

    It 'returns patch when only fixes present' {
        Get-VersionBumpType -Commits @('fix: a', 'chore: b') | Should -Be 'patch'
    }
}

Describe 'Get-NextVersion' {
    It 'bumps the major and resets minor/patch' {
        Get-NextVersion -CurrentVersion '1.4.2' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'bumps the minor and resets patch' {
        Get-NextVersion -CurrentVersion '1.4.2' -BumpType 'minor' | Should -Be '1.5.0'
    }

    It 'bumps the patch only' {
        Get-NextVersion -CurrentVersion '1.4.2' -BumpType 'patch' | Should -Be '1.4.3'
    }

    It 'returns the same core version for a none bump' {
        Get-NextVersion -CurrentVersion '1.4.2' -BumpType 'none' | Should -Be '1.4.2'
    }

    It 'drops any prerelease/build metadata when bumping' {
        Get-NextVersion -CurrentVersion '1.4.2-rc.1+build.9' -BumpType 'patch' | Should -Be '1.4.3'
    }

    It 'throws on an unknown bump type' {
        { Get-NextVersion -CurrentVersion '1.0.0' -BumpType 'sideways' } |
            Should -Throw -ExpectedMessage '*Unknown bump type*'
    }
}

Describe 'Read-CommitLog' {
    BeforeEach {
        $script:logFile = Join-Path $TestDrive 'commits.txt'
    }

    # NB: the literal delimiter token is kept out of the test name because Pester
    # treats angle-bracket tokens in It/Describe names as data-driven placeholders.
    It 'splits commits on the delimiter line and trims each commit' {
        @'
<<<COMMIT>>>
feat: one

body line
<<<COMMIT>>>
fix: two
'@ | Set-Content -Path $script:logFile -Encoding utf8

        $commits = Read-CommitLog -Path $script:logFile
        $commits.Count | Should -Be 2
        $commits[0]    | Should -BeLike 'feat: one*'
        $commits[1]    | Should -Be 'fix: two'
    }

    It 'returns an empty array for an empty file' {
        Set-Content -Path $script:logFile -Value '' -Encoding utf8
        $commits = @(Read-CommitLog -Path $script:logFile)
        $commits.Count | Should -Be 0
    }

    It 'throws a meaningful error when the file is missing' {
        { Read-CommitLog -Path (Join-Path $TestDrive 'nope.txt') } |
            Should -Throw -ExpectedMessage '*Commit log file not found*'
    }
}

Describe 'Get-CurrentVersion' {
    It 'reads a plain VERSION file' {
        $f = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $f -Value '1.2.3' -Encoding utf8
        Get-CurrentVersion -Path $f | Should -Be '1.2.3'
    }

    It 'trims surrounding whitespace/newlines' {
        $f = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $f -Value "  2.3.4  `n" -Encoding utf8
        Get-CurrentVersion -Path $f | Should -Be '2.3.4'
    }

    It 'reads the version field from package.json' {
        $f = Join-Path $TestDrive 'package.json'
        '{ "name": "demo", "version": "4.5.6", "private": true }' |
            Set-Content -Path $f -Encoding utf8
        Get-CurrentVersion -Path $f | Should -Be '4.5.6'
    }

    It 'throws when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $TestDrive 'missing') } |
            Should -Throw -ExpectedMessage '*Version file not found*'
    }

    It 'throws when package.json has no version field' {
        $f = Join-Path $TestDrive 'package.json'
        '{ "name": "demo" }' | Set-Content -Path $f -Encoding utf8
        { Get-CurrentVersion -Path $f } |
            Should -Throw -ExpectedMessage '*no "version" field*'
    }

    It 'throws when the stored version is not valid semver' {
        $f = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $f -Value 'banana' -Encoding utf8
        { Get-CurrentVersion -Path $f } |
            Should -Throw -ExpectedMessage '*not a valid semantic version*'
    }
}

Describe 'Update-VersionFile' {
    It 'overwrites a plain VERSION file with the new version' {
        $f = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $f -Value '1.0.0' -Encoding utf8
        Update-VersionFile -Path $f -NewVersion '1.1.0'
        (Get-Content -Path $f -Raw).Trim() | Should -Be '1.1.0'
    }

    It 'updates only the version field in package.json, preserving other keys' {
        $f = Join-Path $TestDrive 'package.json'
        '{ "name": "demo", "version": "1.0.0", "scripts": { "test": "echo hi" } }' |
            Set-Content -Path $f -Encoding utf8
        Update-VersionFile -Path $f -NewVersion '2.0.0'

        $json = Get-Content -Path $f -Raw | ConvertFrom-Json
        $json.version     | Should -Be '2.0.0'
        $json.name        | Should -Be 'demo'
        $json.scripts.test | Should -Be 'echo hi'
    }
}

Describe 'New-ChangelogEntry' {
    It 'groups commits by type under a versioned, dated header' {
        $commits = @(
            'feat(auth): add SSO login',
            'fix: correct timezone bug',
            'docs: tidy readme'
        )
        $entry = New-ChangelogEntry -Version '1.3.0' -Commits $commits -Date '2026-06-28'

        # Use -Match with escaped text: literal [ ] are wildcard char-classes in -Like.
        $entry | Should -Match ([regex]::Escape('## [1.3.0] - 2026-06-28'))
        $entry | Should -BeLike '*### Features*'
        $entry | Should -BeLike '*add SSO login*'
        $entry | Should -BeLike '*(auth)*'
        $entry | Should -BeLike '*### Bug Fixes*'
        $entry | Should -BeLike '*correct timezone bug*'
    }

    It 'lists breaking changes under their own heading' {
        $commits = @("feat!: drop legacy api`n`nBREAKING CHANGE: removed /v1")
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits $commits -Date '2026-06-28'
        $entry | Should -BeLike '*### BREAKING CHANGES*'
        $entry | Should -BeLike '*removed /v1*'
    }

    It 'notes when there are no notable changes' {
        $entry = New-ChangelogEntry -Version '1.0.1' -Commits @('chore: deps') -Date '2026-06-28'
        $entry | Should -BeLike '*_No notable changes._*'
    }
}

Describe 'Update-Changelog' {
    It 'creates a changelog with a header when none exists, then prepends entries' {
        $f = Join-Path $TestDrive 'CHANGELOG.md'
        Update-Changelog -Path $f -Entry "## [1.0.0] - 2026-06-28`n`n- first"
        $content = Get-Content -Path $f -Raw
        $content | Should -BeLike '*# Changelog*'
        $content | Should -Match ([regex]::Escape('## [1.0.0]'))

        # A newer entry must appear above the older one.
        Update-Changelog -Path $f -Entry "## [1.1.0] - 2026-06-29`n`n- second"
        $content = Get-Content -Path $f -Raw
        $idxNew = $content.IndexOf('## [1.1.0]')
        $idxOld = $content.IndexOf('## [1.0.0]')
        $idxNew | Should -BeLessThan $idxOld
    }
}
