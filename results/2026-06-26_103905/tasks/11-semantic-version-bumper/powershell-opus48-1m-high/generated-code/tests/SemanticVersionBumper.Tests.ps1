#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester tests for the Semantic Version Bumper module.
# Built using red/green TDD: each Describe block was written as a failing test
# first, then the minimum module code was added to make it pass.

BeforeAll {
    # Resolve paths relative to this test file so the suite runs from anywhere.
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:RepoRoot 'src/SemanticVersionBumper.psm1'
    Import-Module $script:ModulePath -Force

    # A scratch directory for tests that read/write files.
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:WorkDir) { Remove-Item $script:WorkDir -Recurse -Force }
}

Describe 'Get-CurrentVersion' {
    Context 'plain text version file' {
        It 'reads a bare semantic version string' {
            $file = Join-Path $script:WorkDir 'VERSION'
            Set-Content -Path $file -Value '1.2.3' -NoNewline
            Get-CurrentVersion -Path $file | Should -Be '1.2.3'
        }

        It 'tolerates trailing whitespace / newlines' {
            $file = Join-Path $script:WorkDir 'VERSION-ws'
            Set-Content -Path $file -Value "  2.0.1`n"
            Get-CurrentVersion -Path $file | Should -Be '2.0.1'
        }

        It 'strips a leading v prefix' {
            $file = Join-Path $script:WorkDir 'VERSION-v'
            Set-Content -Path $file -Value 'v3.4.5' -NoNewline
            Get-CurrentVersion -Path $file | Should -Be '3.4.5'
        }
    }

    Context 'package.json' {
        It 'reads the version property' {
            $file = Join-Path $script:WorkDir 'package.json'
            '{ "name": "demo", "version": "4.5.6" }' | Set-Content -Path $file
            Get-CurrentVersion -Path $file | Should -Be '4.5.6'
        }

        It 'throws when the version property is missing' {
            $dir = Join-Path $script:WorkDir 'noversion'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir 'package.json'
            '{ "name": "demo" }' | Set-Content -Path $file
            { Get-CurrentVersion -Path $file } | Should -Throw "*no 'version' property*"
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-CurrentVersion -Path (Join-Path $script:WorkDir 'nope.txt') } |
                Should -Throw '*not found*'
        }
    }
}

Describe 'Get-CommitsFromLog' {
    # The commit log fixture format is one commit per line: "<hash> <subject>",
    # exactly what `git log --pretty=format:"%h %s"` produces. Blank lines and
    # lines beginning with '#' (comments) are ignored.
    It 'parses hash and subject for each commit line' {
        $file = Join-Path $script:WorkDir 'commits.log'
        @(
            '# a comment line, ignored',
            'abc1234 feat: add login page',
            '',
            'def5678 fix: correct typo'
        ) | Set-Content -Path $file

        $commits = Get-CommitsFromLog -Path $file
        $commits.Count        | Should -Be 2
        $commits[0].Hash      | Should -Be 'abc1234'
        $commits[0].Subject   | Should -Be 'feat: add login page'
        $commits[1].Hash      | Should -Be 'def5678'
        $commits[1].Subject   | Should -Be 'fix: correct typo'
    }

    It 'returns an empty array for an empty log' {
        $file = Join-Path $script:WorkDir 'empty.log'
        Set-Content -Path $file -Value '' -NoNewline
        @(Get-CommitsFromLog -Path $file).Count | Should -Be 0
    }

    It 'throws when the log file is missing' {
        { Get-CommitsFromLog -Path (Join-Path $script:WorkDir 'missing.log') } |
            Should -Throw '*not found*'
    }
}

Describe 'Get-BumpType' {
    # Maps conventional-commit subjects to a bump kind. Precedence is
    # major > minor > patch > none.
    It 'returns patch for a fix commit' {
        Get-BumpType -Subjects @('fix: correct a bug') | Should -Be 'patch'
    }

    It 'returns minor for a feat commit' {
        Get-BumpType -Subjects @('feat: add a thing') | Should -Be 'minor'
    }

    It 'returns major for a breaking change marked with !' {
        Get-BumpType -Subjects @('feat!: drop legacy API') | Should -Be 'major'
    }

    It 'returns major for a fix! breaking change' {
        Get-BumpType -Subjects @('fix!: change behaviour') | Should -Be 'major'
    }

    It 'returns major when a BREAKING CHANGE token is present' {
        Get-BumpType -Subjects @('refactor: rework BREAKING CHANGE: drops X') | Should -Be 'major'
    }

    It 'honours scopes like feat(api): ...' {
        Get-BumpType -Subjects @('feat(api): new endpoint') | Should -Be 'minor'
        Get-BumpType -Subjects @('fix(ui): button')        | Should -Be 'patch'
        Get-BumpType -Subjects @('feat(api)!: breaking')   | Should -Be 'major'
    }

    It 'picks the highest precedence across many commits' {
        Get-BumpType -Subjects @(
            'docs: tweak readme',
            'fix: small bug',
            'feat: cool feature'
        ) | Should -Be 'minor'

        Get-BumpType -Subjects @(
            'fix: a',
            'feat!: b',
            'feat: c'
        ) | Should -Be 'major'
    }

    It 'returns none when no commit warrants a bump' {
        Get-BumpType -Subjects @('docs: x', 'chore: deps', 'style: format') |
            Should -Be 'none'
    }

    It 'returns none for an empty commit set' {
        Get-BumpType -Subjects @() | Should -Be 'none'
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

    It 'returns the same version for a none bump' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws on an unparseable current version' {
        { Get-NextVersion -CurrentVersion 'not-a-version' -BumpType 'patch' } |
            Should -Throw '*not a valid semantic version*'
    }
}

Describe 'Update-VersionFile' {
    It 'overwrites a plain version file with the new version' {
        $file = Join-Path $script:WorkDir 'update-plain'
        Set-Content -Path $file -Value '1.0.0' -NoNewline
        Update-VersionFile -Path $file -NewVersion '1.1.0'
        Get-CurrentVersion -Path $file | Should -Be '1.1.0'
    }

    It 'updates only the version field of a package.json and keeps other fields' {
        $dir = Join-Path $script:WorkDir 'update-pkg'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file = Join-Path $dir 'package.json'
        '{ "name": "demo", "version": "1.0.0", "scripts": { "test": "echo hi" } }' |
            Set-Content -Path $file
        Update-VersionFile -Path $file -NewVersion '2.0.0'

        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
        $json.version      | Should -Be '2.0.0'
        $json.name         | Should -Be 'demo'
        $json.scripts.test | Should -Be 'echo hi'
    }

    It 'throws when the target file does not exist' {
        { Update-VersionFile -Path (Join-Path $script:WorkDir 'ghost') -NewVersion '1.0.0' } |
            Should -Throw '*not found*'
    }
}

Describe 'New-ChangelogEntry' {
    BeforeAll {
        $script:sampleCommits = @(
            [pscustomobject]@{ Hash = 'aaa1111'; Subject = 'feat: add login page' }
            [pscustomobject]@{ Hash = 'bbb2222'; Subject = 'fix(ui): button alignment' }
            [pscustomobject]@{ Hash = 'ccc3333'; Subject = 'feat!: drop legacy API' }
            [pscustomobject]@{ Hash = 'ddd4444'; Subject = 'chore: tidy up' }
        )
        $script:entry = New-ChangelogEntry -Version '2.0.0' `
            -Commits $script:sampleCommits -Date '2026-06-27'
    }

    It 'starts with a version + date header' {
        $script:entry | Should -Match '(?m)^## \[2\.0\.0\] - 2026-06-27\s*$'
    }

    It 'lists breaking changes under a BREAKING CHANGES heading' {
        $script:entry | Should -Match '(?m)^### .*BREAKING CHANGES'
        $script:entry | Should -Match 'drop legacy API \(ccc3333\)'
    }

    It 'lists features under a Features heading with the description and hash' {
        $script:entry | Should -Match '(?m)^### Features'
        $script:entry | Should -Match 'add login page \(aaa1111\)'
    }

    It 'lists fixes under a Bug Fixes heading and preserves the scope' {
        $script:entry | Should -Match '(?m)^### Bug Fixes'
        $script:entry | Should -Match 'ui: button alignment \(bbb2222\)'
    }

    It 'omits non-bumping commits (chore) from the changelog body' {
        $script:entry | Should -Not -Match 'tidy up'
    }

    It 'omits empty sections' {
        $onlyFix = New-ChangelogEntry -Version '1.0.1' `
            -Commits @([pscustomobject]@{ Hash = 'eee5555'; Subject = 'fix: a' }) `
            -Date '2026-06-27'
        $onlyFix | Should -Not -Match 'Features'
        $onlyFix | Should -Not -Match 'BREAKING'
        $onlyFix | Should -Match 'Bug Fixes'
    }
}

Describe 'Invoke-VersionBump (integration)' {
    BeforeEach {
        # A fresh sandbox per test with a version file + commit log fixture.
        $script:sandbox = Join-Path $script:WorkDir ("bump-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:sandbox -Force | Out-Null
        $script:versionFile = Join-Path $script:sandbox 'VERSION'
        $script:logFile     = Join-Path $script:sandbox 'commits.log'
        $script:changelog   = Join-Path $script:sandbox 'CHANGELOG.md'
    }

    It 'performs a minor bump end to end and writes all outputs' {
        Set-Content -Path $script:versionFile -Value '1.1.0' -NoNewline
        @('abc1234 feat: shiny feature', 'def5678 fix: small bug') |
            Set-Content -Path $script:logFile

        $result = Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27'

        $result.PreviousVersion | Should -Be '1.1.0'
        $result.NewVersion      | Should -Be '1.2.0'
        $result.BumpType        | Should -Be 'minor'
        $result.Bumped          | Should -BeTrue

        # Version file updated in place.
        Get-CurrentVersion -Path $script:versionFile | Should -Be '1.2.0'

        # Changelog created and contains the new entry.
        $cl = Get-Content -Path $script:changelog -Raw
        $cl | Should -Match '## \[1\.2\.0\] - 2026-06-27'
        $cl | Should -Match 'shiny feature \(abc1234\)'
    }

    It 'performs a major bump for breaking changes' {
        Set-Content -Path $script:versionFile -Value '1.4.2' -NoNewline
        @('aaa1111 feat!: rewrite the API') | Set-Content -Path $script:logFile

        $result = Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27'

        $result.NewVersion | Should -Be '2.0.0'
        $result.BumpType   | Should -Be 'major'
    }

    It 'performs a patch bump for fixes only' {
        Set-Content -Path $script:versionFile -Value '0.5.0' -NoNewline
        @('aaa1111 fix: a bug', 'bbb2222 docs: notes') | Set-Content -Path $script:logFile

        $result = Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27'

        $result.NewVersion | Should -Be '0.5.1'
        $result.BumpType   | Should -Be 'patch'
    }

    It 'reports no bump and leaves files untouched when nothing qualifies' {
        Set-Content -Path $script:versionFile -Value '3.3.3' -NoNewline
        @('aaa1111 chore: deps', 'bbb2222 docs: readme') | Set-Content -Path $script:logFile

        $result = Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27'

        $result.Bumped     | Should -BeFalse
        $result.NewVersion | Should -Be '3.3.3'
        Get-CurrentVersion -Path $script:versionFile | Should -Be '3.3.3'
        Test-Path $script:changelog | Should -BeFalse
    }

    It 'prepends new entries above existing changelog content' {
        Set-Content -Path $script:versionFile -Value '1.0.0' -NoNewline
        @('aaa1111 feat: first') | Set-Content -Path $script:logFile
        Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27' | Out-Null

        Set-Content -Path $script:versionFile -Value '1.1.0' -NoNewline
        @('bbb2222 feat: second') | Set-Content -Path $script:logFile
        Invoke-VersionBump -VersionFile $script:versionFile `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-28' | Out-Null

        $cl = Get-Content -Path $script:changelog -Raw
        $idxNew = $cl.IndexOf('[1.2.0]')
        $idxOld = $cl.IndexOf('[1.1.0]')
        $idxNew | Should -BeGreaterThan -1
        $idxOld | Should -BeGreaterThan -1
        $idxNew | Should -BeLessThan $idxOld   # newest entry appears first
    }

    It 'works with a package.json version source' {
        $pkgDir = Join-Path $script:sandbox 'pkg'
        New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
        $pkg = Join-Path $pkgDir 'package.json'
        '{ "name": "demo", "version": "2.3.4" }' | Set-Content -Path $pkg
        @('aaa1111 feat: add it') | Set-Content -Path $script:logFile

        $result = Invoke-VersionBump -VersionFile $pkg `
            -CommitLog $script:logFile -ChangelogFile $script:changelog -Date '2026-06-27'

        $result.NewVersion | Should -Be '2.4.0'
        (Get-Content -Path $pkg -Raw | ConvertFrom-Json).version | Should -Be '2.4.0'
    }
}
