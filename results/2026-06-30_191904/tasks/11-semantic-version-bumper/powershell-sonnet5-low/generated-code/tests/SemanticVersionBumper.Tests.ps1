# Pester tests for the Semantic Version Bumper module.
# Written FIRST (red), before the implementation existed, per TDD requirements.
# Run with: Invoke-Pester -Path ./tests

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SemanticVersionBumper.psm1'
    Import-Module $ModulePath -Force

    $FixturesDir = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-CurrentVersion' {
    It 'reads the version from a package.json file' {
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value '{"name":"demo","version":"1.2.3"}'
        Get-CurrentVersion -Path $path | Should -Be '1.2.3'
    }

    It 'reads the version from a plain VERSION text file' {
        $path = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $path -Value '2.5.0'
        Get-CurrentVersion -Path $path | Should -Be '2.5.0'
    }

    It 'throws a meaningful error when the version file does not exist' {
        $path = Join-Path $TestDrive 'missing.json'
        { Get-CurrentVersion -Path $path } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error when package.json has no version field' {
        $path = Join-Path $TestDrive 'noversion.json'
        Set-Content -Path $path -Value '{"name":"demo"}'
        { Get-CurrentVersion -Path $path } | Should -Throw '*version*'
    }

    It 'reads the version from a JSON file that is not named exactly package.json' {
        $path = Join-Path $TestDrive 'demo-package.json'
        Set-Content -Path $path -Value '{"name":"demo","version":"1.1.0"}'
        Get-CurrentVersion -Path $path | Should -Be '1.1.0'
    }

    It 'throws a meaningful error when the version string is not semantic' {
        $path = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $path -Value 'not-a-version'
        { Get-CurrentVersion -Path $path } | Should -Throw '*semantic version*'
    }
}

Describe 'Get-VersionBumpType' {
    It 'returns "major" when a commit message contains BREAKING CHANGE' {
        $commits = @('fix: small tweak', 'feat: add thing', 'feat!: BREAKING CHANGE: rewrite API')
        Get-VersionBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns "major" when a commit uses the ! shorthand for breaking changes' {
        $commits = @('feat!: remove old endpoint')
        Get-VersionBumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns "minor" when the highest-impact commit is a feat' {
        $commits = @('fix: bug squashed', 'feat: add new widget', 'chore: cleanup')
        Get-VersionBumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns "patch" when the highest-impact commit is a fix' {
        $commits = @('fix: bug squashed', 'chore: cleanup', 'docs: update readme')
        Get-VersionBumpType -Commits $commits | Should -Be 'patch'
    }

    It 'returns "none" when there are no conventional commits' {
        $commits = @('chore: cleanup', 'docs: update readme')
        Get-VersionBumpType -Commits $commits | Should -Be 'none'
    }

    It 'throws a meaningful error when given an empty commit list' {
        { Get-VersionBumpType -Commits @() } | Should -Throw '*commit*'
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

    It 'returns the same version unchanged when bump type is none' {
        Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'none' | Should -Be '1.2.3'
    }

    It 'throws a meaningful error for an invalid bump type' {
        { Get-NextVersion -CurrentVersion '1.2.3' -BumpType 'bogus' } | Should -Throw '*bump type*'
    }
}

Describe 'Set-Version' {
    It 'updates the version field inside a package.json file' {
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value '{"name":"demo","version":"1.0.0"}'
        Set-Version -Path $path -NewVersion '1.1.0'
        (Get-Content -Path $path -Raw | ConvertFrom-Json).version | Should -Be '1.1.0'
    }

    It 'updates a plain VERSION text file' {
        $path = Join-Path $TestDrive 'VERSION'
        Set-Content -Path $path -Value '1.0.0'
        Set-Version -Path $path -NewVersion '1.0.1'
        (Get-Content -Path $path -Raw).Trim() | Should -Be '1.0.1'
    }
}

Describe 'New-ChangelogEntry' {
    It 'produces a changelog section with grouped commit types' {
        $commits = @('feat: add login', 'fix: correct typo', 'chore: bump deps')
        $entry = New-ChangelogEntry -Version '1.3.0' -Commits $commits -Date '2026-07-01'

        $entry | Should -Match '## \[1\.3\.0\] - 2026-07-01'
        $entry | Should -Match '### Features'
        $entry | Should -Match '- add login'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Match '- correct typo'
    }

    It 'omits sections for commit types that are not present' {
        $commits = @('feat: add login')
        $entry = New-ChangelogEntry -Version '1.3.0' -Commits $commits -Date '2026-07-01'
        $entry | Should -Not -Match '### Bug Fixes'
    }
}

Describe 'Invoke-VersionBump (end-to-end)' {
    It 'bumps a package.json version based on fixture commits and writes a changelog' {
        $workDir = Join-Path $TestDrive 'proj-feat'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Set-Content -Path (Join-Path $workDir 'package.json') -Value '{"name":"demo","version":"1.0.0"}'
        $changelogPath = Join-Path $workDir 'CHANGELOG.md'
        $commitsFile = Join-Path $FixturesDir 'commits-feat.txt'

        $result = Invoke-VersionBump -VersionFilePath (Join-Path $workDir 'package.json') `
            -CommitLogPath $commitsFile -ChangelogPath $changelogPath -Date '2026-07-01'

        $result.PreviousVersion | Should -Be '1.0.0'
        $result.NewVersion | Should -Be '1.1.0'
        $result.BumpType | Should -Be 'minor'
        (Get-Content (Join-Path $workDir 'package.json') -Raw | ConvertFrom-Json).version | Should -Be '1.1.0'
        Get-Content $changelogPath -Raw | Should -Match '1\.1\.0'
    }

    It 'applies a patch bump from the fixture fix-only commit log' {
        $workDir = Join-Path $TestDrive 'proj-fix'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Set-Content -Path (Join-Path $workDir 'VERSION') -Value '2.0.0'
        $commitsFile = Join-Path $FixturesDir 'commits-fix.txt'

        $result = Invoke-VersionBump -VersionFilePath (Join-Path $workDir 'VERSION') `
            -CommitLogPath $commitsFile -ChangelogPath (Join-Path $workDir 'CHANGELOG.md') -Date '2026-07-01'

        $result.NewVersion | Should -Be '2.0.1'
        $result.BumpType | Should -Be 'patch'
    }

    It 'applies a major bump from the fixture breaking-change commit log' {
        $workDir = Join-Path $TestDrive 'proj-breaking'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Set-Content -Path (Join-Path $workDir 'VERSION') -Value '1.5.2'
        $commitsFile = Join-Path $FixturesDir 'commits-breaking.txt'

        $result = Invoke-VersionBump -VersionFilePath (Join-Path $workDir 'VERSION') `
            -CommitLogPath $commitsFile -ChangelogPath (Join-Path $workDir 'CHANGELOG.md') -Date '2026-07-01'

        $result.NewVersion | Should -Be '2.0.0'
        $result.BumpType | Should -Be 'major'
    }

    It 'throws a meaningful error when the commit log fixture is missing' {
        $workDir = Join-Path $TestDrive 'proj-missing'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Set-Content -Path (Join-Path $workDir 'VERSION') -Value '1.0.0'

        { Invoke-VersionBump -VersionFilePath (Join-Path $workDir 'VERSION') `
            -CommitLogPath (Join-Path $FixturesDir 'does-not-exist.txt') `
            -ChangelogPath (Join-Path $workDir 'CHANGELOG.md') -Date '2026-07-01' } | Should -Throw '*not found*'
    }
}
