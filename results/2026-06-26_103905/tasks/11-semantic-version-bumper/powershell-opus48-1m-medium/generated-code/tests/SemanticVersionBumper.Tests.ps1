# Pester tests for the Semantic Version Bumper.
# Developed red/green TDD style: each Describe block was written as a failing
# test first, then the minimum code added to SemanticVersionBumper.psm1 to pass.

BeforeAll {
    # Resolve the module relative to this test file so it works from any CWD.
    $ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'SemanticVersionBumper.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-CurrentVersion' {
    It 'reads a plain version string from a version.txt file' {
        $file = Join-Path $TestDrive 'version.txt'
        Set-Content -Path $file -Value '1.2.3'
        Get-CurrentVersion -Path $file | Should -Be '1.2.3'
    }

    It 'trims surrounding whitespace/newlines' {
        $file = Join-Path $TestDrive 'version2.txt'
        Set-Content -Path $file -Value "  4.5.6`n"
        Get-CurrentVersion -Path $file | Should -Be '4.5.6'
    }

    It 'reads the version field from a package.json file' {
        $file = Join-Path $TestDrive 'package.json'
        '{ "name": "demo", "version": "2.0.1" }' | Set-Content -Path $file
        Get-CurrentVersion -Path $file | Should -Be '2.0.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $TestDrive 'nope.txt') } |
            Should -Throw '*not found*'
    }

    It 'throws when the file is empty' {
        $file = Join-Path $TestDrive 'empty.txt'
        Set-Content -Path $file -Value ''
        { Get-CurrentVersion -Path $file } | Should -Throw '*empty*'
    }
}

Describe 'Get-VersionBumpType' {
    It 'returns "patch" for a fix commit' {
        Get-VersionBumpType -Commits @('fix: correct off-by-one') | Should -Be 'patch'
    }

    It 'returns "minor" for a feat commit' {
        Get-VersionBumpType -Commits @('feat: add export button') | Should -Be 'minor'
    }

    It 'returns "major" when a commit uses the breaking "!" marker' {
        Get-VersionBumpType -Commits @('feat!: drop v1 API') | Should -Be 'major'
    }

    It 'returns "major" when a commit body contains BREAKING CHANGE' {
        $commit = "refactor: rework auth`n`nBREAKING CHANGE: tokens now required"
        Get-VersionBumpType -Commits @($commit) | Should -Be 'major'
    }

    It 'picks the highest precedence bump across mixed commits' {
        $commits = @('fix: a', 'feat: b', 'chore: c')
        Get-VersionBumpType -Commits $commits | Should -Be 'minor'
    }

    It 'honours scoped conventional commits like feat(api):' {
        Get-VersionBumpType -Commits @('feat(api): scoped feature') | Should -Be 'minor'
    }

    It 'returns "none" when no commit warrants a bump' {
        Get-VersionBumpType -Commits @('chore: tidy', 'docs: readme') | Should -Be 'none'
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

    It 'tolerates a leading v prefix and preserves a clean output' {
        Get-NextVersion -CurrentVersion 'v0.9.9' -BumpType 'minor' | Should -Be '0.10.0'
    }

    It 'throws on a malformed version' {
        { Get-NextVersion -CurrentVersion 'not.a.version' -BumpType 'patch' } |
            Should -Throw '*not a valid*'
    }
}

Describe 'Update-VersionFile' {
    It 'overwrites a plain version.txt file' {
        $file = Join-Path $TestDrive 'upd.txt'
        Set-Content -Path $file -Value '1.0.0'
        Update-VersionFile -Path $file -NewVersion '1.1.0'
        Get-CurrentVersion -Path $file | Should -Be '1.1.0'
    }

    It 'updates only the version field inside package.json, preserving other keys' {
        $file = Join-Path $TestDrive 'pkg-upd.json'
        '{ "name": "demo", "version": "1.0.0", "private": true }' | Set-Content -Path $file
        Update-VersionFile -Path $file -NewVersion '1.1.0'
        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
        $json.version | Should -Be '1.1.0'
        $json.name    | Should -Be 'demo'
        $json.private | Should -BeTrue
    }
}

Describe 'New-ChangelogEntry' {
    It 'groups commits under Features / Fixes / Breaking headings' {
        $commits = @('feat: add A', 'fix: repair B', 'feat!: remove C')
        $entry = New-ChangelogEntry -Version '1.3.0' -Commits $commits -Date '2026-06-26'

        $entry | Should -Match '## \[1\.3\.0\] - 2026-06-26'
        $entry | Should -Match '### Features'
        $entry | Should -Match 'add A'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Match 'repair B'
        $entry | Should -Match '### BREAKING CHANGES'
        $entry | Should -Match 'remove C'
    }

    It 'omits empty sections' {
        $entry = New-ChangelogEntry -Version '1.0.1' -Commits @('fix: only a fix') -Date '2026-06-26'
        $entry | Should -Match '### Bug Fixes'
        $entry | Should -Not -Match '### Features'
    }
}

Describe 'Get-CommitsFromLog' {
    It 'reads non-empty lines from a commit log file as commit messages' {
        $file = Join-Path $TestDrive 'commits.txt'
        Set-Content -Path $file -Value "feat: one`n`nfix: two`n"
        $commits = Get-CommitsFromLog -Path $file
        $commits.Count | Should -Be 2
        $commits[0] | Should -Be 'feat: one'
    }

    It 'splits multi-line commits separated by a NUL/record separator' {
        # git log -z style: commits separated by NUL. We support a literal
        # "---COMMIT---" delimiter for the fixtures so commit bodies survive.
        $file = Join-Path $TestDrive 'commits2.txt'
        $content = "feat: a`nbody line---COMMIT---fix: b"
        Set-Content -Path $file -Value $content -NoNewline
        $commits = Get-CommitsFromLog -Path $file
        $commits.Count | Should -Be 2
        $commits[0] | Should -Match 'body line'
    }
}

Describe 'Invoke-VersionBump (integration)' {
    It 'reads, bumps, writes and produces a changelog in one call' {
        $dir = Join-Path $TestDrive 'integ'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $versionFile   = Join-Path $dir 'version.txt'
        $commitsFile   = Join-Path $dir 'commits.txt'
        $changelogFile = Join-Path $dir 'CHANGELOG.md'
        Set-Content -Path $versionFile -Value '1.1.0'
        Set-Content -Path $commitsFile -Value 'feat: shiny new thing'

        $result = Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath $commitsFile -ChangelogPath $changelogFile -Date '2026-06-26'

        $result.OldVersion | Should -Be '1.1.0'
        $result.NewVersion | Should -Be '1.2.0'
        $result.BumpType   | Should -Be 'minor'
        Get-CurrentVersion -Path $versionFile | Should -Be '1.2.0'
        (Get-Content -Path $changelogFile -Raw) | Should -Match 'shiny new thing'
    }
}
