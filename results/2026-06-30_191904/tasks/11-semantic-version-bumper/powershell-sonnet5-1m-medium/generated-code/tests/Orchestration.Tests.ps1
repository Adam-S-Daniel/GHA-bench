BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
    $fixturesDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Invoke-VersionBump' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $script:versionFile = Join-Path $tempDir 'version.json'
        Set-Content -Path $versionFile -Value '{"version":"1.2.3"}'
        $script:changelogFile = Join-Path $tempDir 'CHANGELOG.md'
    }

    AfterEach {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'bumps the minor version for a feat commit log and writes version + changelog files' {
        $result = Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-feat.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-01'

        $result.OldVersion | Should -Be '1.2.3'
        $result.NewVersion | Should -Be '1.3.0'
        $result.BumpType | Should -Be 'minor'

        (Get-Content $versionFile -Raw | ConvertFrom-Json).version | Should -Be '1.3.0'
        (Get-Content $changelogFile -Raw) | Should -Match '## \[1\.3\.0\] - 2026-07-01'
    }

    It 'bumps the major version for a breaking commit log' {
        $result = Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-breaking.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-01'

        $result.NewVersion | Should -Be '2.0.0'
    }

    It 'bumps the patch version for a fix-only commit log' {
        $result = Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-fix.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-01'

        $result.NewVersion | Should -Be '1.2.4'
    }

    It 'prepends new entries above older ones on repeated runs' {
        Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-fix.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-01' | Out-Null

        Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-feat.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-02' | Out-Null

        $content = Get-Content $changelogFile -Raw
        $content.IndexOf('1.3.0') | Should -BeLessThan $content.IndexOf('1.2.4')
    }

    It 'does not change the version file when there are no release-worthy commits' {
        $result = Invoke-VersionBump -VersionFilePath $versionFile `
            -CommitLogPath (Join-Path $fixturesDir 'commits-none.txt') `
            -ChangelogPath $changelogFile `
            -Date '2026-07-01'

        $result.NewVersion | Should -Be '1.2.3'
        $result.BumpType | Should -Be 'none'
    }
}
