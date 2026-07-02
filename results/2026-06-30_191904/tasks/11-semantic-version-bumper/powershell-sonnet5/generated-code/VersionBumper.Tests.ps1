<#
    Pester unit tests for the VersionBumper module.

    These tests drive the module's design via red/green TDD: each Describe
    block below was written before the corresponding function existed in
    VersionBumper.psm1, then the minimum code was added to make it pass.

    Fixture commit logs live under ./fixtures and simulate `git log
    --pretty=%s` output (one conventional-commit subject line per commit).
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot 'VersionBumper.psm1'
    Import-Module $script:ModulePath -Force
    $script:FixturesPath = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Get-CurrentVersion' {
    Context 'plain text VERSION file' {
        It 'reads a semantic version from a plain text file' {
            $path = Join-Path $script:FixturesPath 'VERSION'
            Get-CurrentVersion -Path $path | Should -Be '1.1.0'
        }
    }

    Context 'package.json file' {
        It 'reads the version field from package.json' {
            $path = Join-Path $script:FixturesPath 'package.json'
            Get-CurrentVersion -Path $path | Should -Be '2.3.4'
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-CurrentVersion -Path (Join-Path $script:FixturesPath 'does-not-exist.txt') } |
                Should -Throw '*not found*'
        }

        It 'throws a meaningful error when the version string is not valid semver' {
            $path = Join-Path $script:FixturesPath 'invalid-version.txt'
            { Get-CurrentVersion -Path $path } | Should -Throw '*not a valid semantic version*'
        }

        It 'throws a meaningful error when package.json has no version field' {
            $path = Join-Path $script:FixturesPath 'package-no-version.json'
            { Get-CurrentVersion -Path $path } | Should -Throw "*no 'version' field*"
        }
    }
}

Describe 'Get-NextVersion' {
    It 'increments the patch number for a patch bump' {
        Get-NextVersion -CurrentVersion '1.1.0' -BumpType 'patch' | Should -Be '1.1.1'
    }

    It 'increments the minor number and resets patch for a minor bump' {
        Get-NextVersion -CurrentVersion '1.1.0' -BumpType 'minor' | Should -Be '1.2.0'
    }

    It 'increments the major number and resets minor/patch for a major bump' {
        Get-NextVersion -CurrentVersion '1.1.5' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'resets lower components even when they are non-zero' {
        Get-NextVersion -CurrentVersion '1.9.7' -BumpType 'minor' | Should -Be '1.10.0'
    }

    It 'throws a meaningful error for an invalid current version' {
        { Get-NextVersion -CurrentVersion 'not-a-version' -BumpType 'patch' } |
            Should -Throw '*not a valid semantic version*'
    }

    It 'rejects an unrecognized bump type' {
        { Get-NextVersion -CurrentVersion '1.1.0' -BumpType 'epic' } | Should -Throw
    }
}

Describe 'Get-CommitMessagesFromFile' {
    It 'reads one commit message per non-blank line' {
        $path = Join-Path $script:FixturesPath 'commits-feat-only.txt'
        $messages = Get-CommitMessagesFromFile -Path $path
        $messages.Count | Should -Be 3
        $messages | Should -Contain 'feat: add user dashboard widget'
    }

    It 'throws a meaningful error when the commit log file does not exist' {
        { Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'no-such-log.txt') } |
            Should -Throw '*not found*'
    }

    It 'still returns an array (not an unwrapped scalar) when exactly one line survives' {
        # Regression test: PowerShell enumerates arrays placed on the
        # output stream, so a naive `return @(...)` silently unwraps to a
        # bare string when the collection has exactly one element.
        $path = Join-Path $script:FixturesPath 'commits-single.txt'
        $messages = Get-CommitMessagesFromFile -Path $path
        ($messages -is [array]) | Should -BeTrue
        $messages.Count | Should -Be 1
        $messages[0] | Should -Be 'feat: add single new widget'
    }
}

Describe 'Get-BumpType' {
    It 'returns "minor" when only feat commits are present (plus chores/docs)' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-feat-only.txt')
        Get-BumpType -CommitMessages $messages | Should -Be 'minor'
    }

    It 'returns "patch" when only fix commits are present' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-fix-only.txt')
        Get-BumpType -CommitMessages $messages | Should -Be 'patch'
    }

    It 'returns "major" when a "!" breaking marker is present' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-breaking.txt')
        Get-BumpType -CommitMessages $messages | Should -Be 'major'
    }

    It 'returns "major" when a BREAKING CHANGE footer is present' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-breaking-footer.txt')
        Get-BumpType -CommitMessages $messages | Should -Be 'major'
    }

    It 'picks the highest-priority bump when commit types are mixed' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-mixed.txt')
        Get-BumpType -CommitMessages $messages | Should -Be 'minor'
    }

    It 'returns $null when no commits affect the version' {
        $messages = Get-CommitMessagesFromFile -Path (Join-Path $script:FixturesPath 'commits-none.txt')
        Get-BumpType -CommitMessages $messages | Should -BeNullOrEmpty
    }

    It 'returns $null for an empty commit list' {
        Get-BumpType -CommitMessages @() | Should -BeNullOrEmpty
    }
}

Describe 'Update-VersionFile' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'overwrites a plain text VERSION file with the new version' {
        $path = Join-Path $script:TempDir 'VERSION'
        Set-Content -Path $path -Value '1.1.0' -NoNewline
        Update-VersionFile -Path $path -NewVersion '1.2.0'
        (Get-Content -Path $path -Raw).Trim() | Should -Be '1.2.0'
    }

    It 'updates only the version field of a package.json file, preserving other fields' {
        $path = Join-Path $script:TempDir 'package.json'
        Copy-Item -Path (Join-Path $script:FixturesPath 'package.json') -Destination $path
        Update-VersionFile -Path $path -NewVersion '3.0.0'
        $json = Get-Content -Path $path -Raw | ConvertFrom-Json
        $json.version | Should -Be '3.0.0'
        $json.name | Should -Be 'mock-package'
    }
}

Describe 'New-ChangelogEntry' {
    It 'groups commits under Breaking Changes, Features, and Bug Fixes headings' {
        $messages = @(
            'feat!: redesign auth API',
            'feat: add csv export',
            'fix: correct timezone bug',
            'chore: bump deps'
        )
        $entry = New-ChangelogEntry -Version '2.0.0' -CommitMessages $messages -Date '2026-06-30'

        $entry | Should -Match '^## \[2\.0\.0\] - 2026-06-30'
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match '- redesign auth API'
        $entry | Should -Match '### Features'
        $entry | Should -Match '- add csv export'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Match '- correct timezone bug'
        $entry | Should -Not -Match 'bump deps'
    }

    It 'omits a heading entirely when there are no commits of that kind' {
        $entry = New-ChangelogEntry -Version '1.1.1' -CommitMessages @('fix: small bug') -Date '2026-06-30'
        $entry | Should -Not -Match '### Features'
        $entry | Should -Not -Match '### Breaking Changes'
    }
}

Describe 'Add-ChangelogEntry' {
    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempDir | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates a new changelog file with a top-level header when none exists' {
        $path = Join-Path $script:TempDir 'CHANGELOG.md'
        Add-ChangelogEntry -Path $path -Entry "## [1.0.0] - 2026-06-30`n`n- first release"
        $content = Get-Content -Path $path -Raw
        $content | Should -Match '^# Changelog'
        $content | Should -Match '## \[1\.0\.0\] - 2026-06-30'
    }

    It 'prepends new entries above existing ones' {
        $path = Join-Path $script:TempDir 'CHANGELOG.md'
        Add-ChangelogEntry -Path $path -Entry '## [1.0.0] - 2026-06-30'
        Add-ChangelogEntry -Path $path -Entry '## [1.1.0] - 2026-07-01'
        $content = Get-Content -Path $path -Raw
        $content.IndexOf('1.1.0') | Should -BeLessThan $content.IndexOf('1.0.0')
    }
}

Describe 'Get-CommitMessagesFromGit' {
    BeforeEach {
        # A throwaway git repo gives us a real `git log` to read from,
        # rather than mocking the git CLI -- this exercises the actual
        # command and format-string we use in production.
        $script:GitRepo = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:GitRepo | Out-Null
        Push-Location $script:GitRepo
        git init --quiet --initial-branch=main 2>&1 | Out-Null
        git config user.email 'test@example.com' 2>&1 | Out-Null
        git config user.name 'Test' 2>&1 | Out-Null
    }

    AfterEach {
        Pop-Location
        Remove-Item -Path $script:GitRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reads commit subjects and bodies from the full git history when no tag exists' {
        'a' | Out-File 'a.txt'
        git add . 2>&1 | Out-Null
        git commit --quiet -m 'chore: initial commit' 2>&1 | Out-Null
        'b' | Out-File 'b.txt'
        git add . 2>&1 | Out-Null
        git commit --quiet -m 'feat: add b' 2>&1 | Out-Null

        $messages = Get-CommitMessagesFromGit
        $messages.Count | Should -Be 2
        $messages | Should -Contain 'feat: add b'
    }

    It 'includes multi-line commit bodies so BREAKING CHANGE footers are visible' {
        'a' | Out-File 'a.txt'
        git add . 2>&1 | Out-Null
        git commit --quiet -m 'feat: new auth system' -m 'BREAKING CHANGE: removes legacy login endpoint' 2>&1 | Out-Null

        $messages = Get-CommitMessagesFromGit
        # The subject + body of this single commit must stay together as one
        # array element -- splitting them apart would (here) still happen to
        # detect "major", masking a bug where multi-commit ranges get
        # mis-split on internal blank lines instead of on commit boundaries.
        ($messages -is [array]) | Should -BeTrue
        $messages.Count | Should -Be 1
        $messages[0] | Should -Match 'feat: new auth system'
        $messages[0] | Should -Match 'BREAKING CHANGE: removes legacy login endpoint'
        Get-BumpType -CommitMessages $messages | Should -Be 'major'
    }

    It 'only reads commits since the last tag when one exists' {
        'a' | Out-File 'a.txt'
        git add . 2>&1 | Out-Null
        git commit --quiet -m 'feat: pre-tag feature' 2>&1 | Out-Null
        git tag v1.0.0 2>&1 | Out-Null
        'b' | Out-File 'b.txt'
        git add . 2>&1 | Out-Null
        git commit --quiet -m 'fix: post-tag fix' 2>&1 | Out-Null

        $messages = Get-CommitMessagesFromGit
        $messages | Should -Not -Contain 'feat: pre-tag feature'
        $messages | Should -Contain 'fix: post-tag fix'
    }
}
