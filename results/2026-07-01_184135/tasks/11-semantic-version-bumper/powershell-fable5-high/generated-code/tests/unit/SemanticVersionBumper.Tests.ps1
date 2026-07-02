<#
.SYNOPSIS
    Unit tests for the SemanticVersionBumper module (TDD, red/green).

.DESCRIPTION
    Tests are added one cycle at a time following red/green TDD:
    each Describe block was written BEFORE the implementation it exercises.
#>

BeforeAll {
    # Import the module under test fresh for every run so edits are picked up.
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'SemanticVersionBumper.psm1'
    Import-Module $modulePath -Force

    # Mock commit-log fixtures (commit messages delimited by "---" lines).
    $script:FixtureDir = Join-Path $PSScriptRoot '..' '..' 'fixtures'
    $script:CommitLogDir = Join-Path $FixtureDir 'commit-logs'
}

Describe 'ConvertFrom-SemVer' {
    It 'parses "<Version>" into major=<Major> minor=<Minor> patch=<Patch>' -ForEach @(
        @{ Version = '1.2.3';   Major = 1;  Minor = 2; Patch = 3 }
        @{ Version = '0.0.1';   Major = 0;  Minor = 0; Patch = 1 }
        @{ Version = '10.20.30'; Major = 10; Minor = 20; Patch = 30 }
    ) {
        $result = ConvertFrom-SemVer -Version $Version
        $result.Major | Should -Be $Major
        $result.Minor | Should -Be $Minor
        $result.Patch | Should -Be $Patch
    }

    It 'throws a meaningful error for invalid version "<Bad>"' -ForEach @(
        @{ Bad = 'not-a-version' }
        @{ Bad = '1.2' }
        @{ Bad = '1.2.3.4' }
        @{ Bad = '' }
    ) {
        { ConvertFrom-SemVer -Version $Bad } |
            Should -Throw -ExpectedMessage "*not a valid semantic version*"
    }
}

Describe 'Split-CommitLog' {
    It 'splits a commit log fixture into individual commit messages' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'feat.txt')
        $commits | Should -HaveCount 3
        $commits[0] | Should -Be 'feat: add user login endpoint'
        $commits[2] | Should -Be 'chore: update dependencies'
    }

    It 'keeps multi-line commit bodies together' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'breaking.txt')
        $commits | Should -HaveCount 3
        $commits[1] | Should -Match 'BREAKING CHANGE: all v1 routes now return 410 Gone'
    }

    It 'throws a meaningful error when the log file does not exist' {
        { Split-CommitLog -Path (Join-Path $CommitLogDir 'missing.txt') } |
            Should -Throw -ExpectedMessage '*Commit log file not found*'
    }
}

Describe 'Get-BumpType' {
    It 'returns minor for feat commits' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'feat.txt')
        Get-BumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns patch for fix commits' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'fix.txt')
        Get-BumpType -Commits $commits | Should -Be 'patch'
    }

    It 'returns major when any commit is breaking (bang or footer)' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'breaking.txt')
        Get-BumpType -Commits $commits | Should -Be 'major'
    }

    It 'returns minor when feat and fix are mixed (highest wins)' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'mixed.txt')
        Get-BumpType -Commits $commits | Should -Be 'minor'
    }

    It 'returns none when no release-worthy commits are present' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'none.txt')
        Get-BumpType -Commits $commits | Should -Be 'none'
    }

    It 'detects breaking via "fix!:" subject marker on its own' {
        Get-BumpType -Commits @('fix!: change config file format') | Should -Be 'major'
    }

    It 'detects breaking via BREAKING-CHANGE footer variant' {
        Get-BumpType -Commits @("chore: rework build`n`nBREAKING-CHANGE: output moved to dist/") |
            Should -Be 'major'
    }
}

Describe 'Step-Version' {
    It 'bumps <Bump> from <From> to <Expected>' -ForEach @(
        @{ From = '1.1.0'; Bump = 'minor'; Expected = '1.2.0' }
        @{ From = '2.3.4'; Bump = 'patch'; Expected = '2.3.5' }
        @{ From = '1.5.2'; Bump = 'major'; Expected = '2.0.0' }
        @{ From = '0.9.9'; Bump = 'minor'; Expected = '0.10.0' }
        @{ From = '3.2.1'; Bump = 'none';  Expected = '3.2.1' }
    ) {
        Step-Version -Version $From -BumpType $Bump | Should -Be $Expected
    }
}

Describe 'Get-CurrentVersion / Set-VersionFile' {
    BeforeEach {
        # Work on throwaway copies so fixtures stay pristine.
        $script:workDir = Join-Path ([IO.Path]::GetTempPath()) "svb-test-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Copy-Item (Join-Path $FixtureDir 'version-files' '*') $workDir
    }
    AfterEach {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }

    It 'reads the version from a plain VERSION file' {
        Get-CurrentVersion -Path (Join-Path $workDir 'VERSION') | Should -Be '1.1.0'
    }

    It 'reads the version field from package.json' {
        Get-CurrentVersion -Path (Join-Path $workDir 'package.json') | Should -Be '1.1.0'
    }

    It 'throws a meaningful error when the version file is missing' {
        { Get-CurrentVersion -Path (Join-Path $workDir 'nope.txt') } |
            Should -Throw -ExpectedMessage '*Version file not found*'
    }

    It 'throws a meaningful error when package.json has no version field' {
        Set-Content (Join-Path $workDir 'package.json') '{ "name": "x" }'
        { Get-CurrentVersion -Path (Join-Path $workDir 'package.json') } |
            Should -Throw -ExpectedMessage '*does not contain a "version" field*'
    }

    It 'throws a meaningful error when package.json is invalid JSON' {
        Set-Content (Join-Path $workDir 'package.json') '{ not json'
        { Get-CurrentVersion -Path (Join-Path $workDir 'package.json') } |
            Should -Throw -ExpectedMessage '*not valid JSON*'
    }

    It 'writes the new version to a plain VERSION file' {
        $path = Join-Path $workDir 'VERSION'
        Set-VersionFile -Path $path -Version '1.2.0'
        Get-CurrentVersion -Path $path | Should -Be '1.2.0'
    }

    It 'updates package.json version while preserving other fields' {
        $path = Join-Path $workDir 'package.json'
        Set-VersionFile -Path $path -Version '2.0.0'
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.version | Should -Be '2.0.0'
        $json.name | Should -Be 'demo-app'
        $json.scripts.test | Should -Be 'echo ok'
    }
}

Describe 'New-ChangelogEntry' {
    It 'groups commits under Breaking Changes / Features / Bug Fixes' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'breaking.txt')
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits $commits -Date '2026-07-02'

        $entry | Should -Match ([regex]::Escape('## [2.0.0] - 2026-07-02'))
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match '- drop legacy v1 API endpoints'
        $entry | Should -Match '- add replacement v2 endpoints'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Match '- correct pagination off-by-one'
    }

    It 'omits empty sections' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'fix.txt')
        $entry = New-ChangelogEntry -Version '1.1.1' -Commits $commits -Date '2026-07-02'

        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Not -Match '### Features'
        $entry | Should -Not -Match '### Breaking Changes'
    }

    It 'includes the commit scope in the bullet when present' {
        $commits = Split-CommitLog -Path (Join-Path $CommitLogDir 'mixed.txt')
        $entry = New-ChangelogEntry -Version '1.2.0' -Commits $commits -Date '2026-07-02'

        $entry | Should -Match ([regex]::Escape('- **api:** add rate limiting headers'))
        $entry | Should -Match ([regex]::Escape('- **db:** close connection pool on shutdown'))
    }
}

Describe 'Invoke-VersionBump (end-to-end)' {
    BeforeEach {
        $script:workDir = Join-Path ([IO.Path]::GetTempPath()) "svb-e2e-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Copy-Item (Join-Path $FixtureDir 'version-files' '*') $workDir
    }
    AfterEach {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }

    It 'bumps 1.1.0 to 1.2.0 for the feat fixture and updates all artifacts' {
        $versionFile = Join-Path $workDir 'VERSION'
        $changelog = Join-Path $workDir 'CHANGELOG.md'

        $result = Invoke-VersionBump `
            -VersionFile $versionFile `
            -CommitLogFile (Join-Path $CommitLogDir 'feat.txt') `
            -ChangelogFile $changelog `
            -Date '2026-07-02'

        $result | Should -Be '1.2.0'
        Get-CurrentVersion -Path $versionFile | Should -Be '1.2.0'
        $log = Get-Content $changelog -Raw
        $log | Should -Match ([regex]::Escape('## [1.2.0] - 2026-07-02'))
        $log | Should -Match '- add user login endpoint'
    }

    It 'works against package.json as the version file' {
        $versionFile = Join-Path $workDir 'package.json'

        $result = Invoke-VersionBump `
            -VersionFile $versionFile `
            -CommitLogFile (Join-Path $CommitLogDir 'breaking.txt') `
            -ChangelogFile (Join-Path $workDir 'CHANGELOG.md') `
            -Date '2026-07-02'

        $result | Should -Be '2.0.0'
        (Get-Content $versionFile -Raw | ConvertFrom-Json).version | Should -Be '2.0.0'
    }

    It 'prepends new entries above older ones in an existing changelog' {
        $versionFile = Join-Path $workDir 'VERSION'
        $changelog = Join-Path $workDir 'CHANGELOG.md'
        Set-Content $changelog "# Changelog`n`n## [1.1.0] - 2026-06-01`n`n### Features`n- older entry`n"

        Invoke-VersionBump -VersionFile $versionFile `
            -CommitLogFile (Join-Path $CommitLogDir 'fix.txt') `
            -ChangelogFile $changelog -Date '2026-07-02' | Out-Null

        $log = Get-Content $changelog -Raw
        $log.IndexOf('[1.1.1]') | Should -BeLessThan $log.IndexOf('[1.1.0]')
        $log | Should -Match '- older entry'
    }

    It 'leaves everything untouched and returns the current version when no bump is needed' {
        $versionFile = Join-Path $workDir 'VERSION'
        $changelog = Join-Path $workDir 'CHANGELOG.md'

        $result = Invoke-VersionBump -VersionFile $versionFile `
            -CommitLogFile (Join-Path $CommitLogDir 'none.txt') `
            -ChangelogFile $changelog -Date '2026-07-02'

        $result | Should -Be '1.1.0'
        Get-CurrentVersion -Path $versionFile | Should -Be '1.1.0'
        Test-Path $changelog | Should -BeFalse
    }

    It 'surfaces a meaningful error for a corrupt version file' {
        $versionFile = Join-Path $workDir 'VERSION'
        Set-Content $versionFile 'garbage'

        { Invoke-VersionBump -VersionFile $versionFile `
            -CommitLogFile (Join-Path $CommitLogDir 'feat.txt') `
            -ChangelogFile (Join-Path $workDir 'CHANGELOG.md') } |
            Should -Throw -ExpectedMessage '*not a valid semantic version*'
    }
}
