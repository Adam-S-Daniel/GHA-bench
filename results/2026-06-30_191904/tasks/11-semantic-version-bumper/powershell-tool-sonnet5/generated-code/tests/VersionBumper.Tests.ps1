# Pester unit tests for the VersionBumper module.
# TDD workflow: each Describe block below was written before its
# corresponding implementation existed in src/VersionBumper.psm1 (red),
# then the minimum code was added to make it pass (green).
#
# Run with:  Invoke-Pester ./tests/VersionBumper.Tests.ps1 -Output Detailed

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'VersionBumper.psm1'
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-VersionFromFile' {

    Context 'Plain text VERSION file' {
        BeforeAll {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "VERSION-$(Get-Random)"
            Set-Content -Path $tempFile -Value '1.2.3' -NoNewline
        }
        AfterAll {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }

        It 'reads a bare semantic version string' {
            Get-VersionFromFile -Path $tempFile | Should -Be '1.2.3'
        }
    }

    Context 'package.json file' {
        BeforeAll {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "package-$(Get-Random).json"
            '{"name": "demo", "version": "2.5.0"}' | Set-Content -Path $tempFile
        }
        AfterAll {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }

        It 'extracts the version field from JSON' {
            Get-VersionFromFile -Path $tempFile | Should -Be '2.5.0'
        }
    }

    Context 'package.json fixture' {
        It 'extracts the version field from the checked-in fixtures/package.json' {
            Get-VersionFromFile -Path (Join-Path $FixturesPath 'package.json') | Should -Be '1.0.0'
        }
    }

    Context 'Missing file' {
        It 'throws a meaningful error' {
            { Get-VersionFromFile -Path '/nonexistent/VERSION' } | Should -Throw '*not found*'
        }
    }

    Context 'package.json without a version field' {
        BeforeAll {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "package-$(Get-Random).json"
            '{"name": "demo"}' | Set-Content -Path $tempFile
        }
        AfterAll {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }

        It 'throws a meaningful error' {
            { Get-VersionFromFile -Path $tempFile } | Should -Throw '*version*'
        }
    }
}

Describe 'Get-CommitMessages' {

    Context 'Reading from a fixture log file' {
        It 'returns one trimmed message per non-empty line' {
            $path = Join-Path $FixturesPath 'commits-minor.log'
            $messages = Get-CommitMessages -Path $path
            $messages.Count | Should -Be 2
            $messages[0] | Should -Be 'feat: add support for scoped packages'
        }

        It 'ignores blank lines' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "commits-$(Get-Random).log"
            "fix: a`n`n`nfix: b`n" | Set-Content -Path $tempFile
            try {
                (Get-CommitMessages -Path $tempFile).Count | Should -Be 2
            } finally {
                Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Missing fixture file' {
        It 'throws a meaningful error' {
            { Get-CommitMessages -Path '/nonexistent/commits.log' } | Should -Throw '*not found*'
        }
    }
}

Describe 'Get-BumpType' {

    It 'returns Patch when only fix commits are present' {
        $messages = Get-CommitMessages -Path (Join-Path $FixturesPath 'commits-patch.log')
        Get-BumpType -Messages $messages | Should -Be 'Patch'
    }

    It 'returns Minor when a feat commit is present' {
        $messages = Get-CommitMessages -Path (Join-Path $FixturesPath 'commits-minor.log')
        Get-BumpType -Messages $messages | Should -Be 'Minor'
    }

    It 'returns Major when a "!" breaking marker is present' {
        Get-BumpType -Messages @('feat!: redesign API') | Should -Be 'Major'
    }

    It 'returns Major when a BREAKING CHANGE footer line is present' {
        Get-BumpType -Messages @('feat: add thing', 'BREAKING CHANGE: removed old thing') | Should -Be 'Major'
    }

    It 'returns Major when mixed with feat and fix (major takes priority)' {
        $messages = Get-CommitMessages -Path (Join-Path $FixturesPath 'commits-major.log')
        Get-BumpType -Messages $messages | Should -Be 'Major'
    }

    It 'returns None when no conventional commit markers are present' {
        $messages = Get-CommitMessages -Path (Join-Path $FixturesPath 'commits-none.log')
        Get-BumpType -Messages $messages | Should -Be 'None'
    }

    It 'returns None for an empty message list' {
        Get-BumpType -Messages @() | Should -Be 'None'
    }
}

Describe 'Get-NextVersion' {

    It 'bumps the major component and resets minor/patch' {
        Get-NextVersion -CurrentVersion '1.4.7' -BumpType 'Major' | Should -Be '2.0.0'
    }

    It 'bumps the minor component and resets patch' {
        Get-NextVersion -CurrentVersion '1.4.7' -BumpType 'Minor' | Should -Be '1.5.0'
    }

    It 'bumps the patch component' {
        Get-NextVersion -CurrentVersion '1.4.7' -BumpType 'Patch' | Should -Be '1.4.8'
    }

    It 'returns the same version unchanged for None' {
        Get-NextVersion -CurrentVersion '1.4.7' -BumpType 'None' | Should -Be '1.4.7'
    }

    It 'throws a meaningful error for a malformed version string' {
        { Get-NextVersion -CurrentVersion 'not-a-version' -BumpType 'Patch' } | Should -Throw '*semantic version*'
    }
}

Describe 'New-ChangelogEntry' {

    BeforeAll {
        $messages = @(
            'feat!: redesign public API surface'
            'fix: clean up obsolete code paths'
            'BREAKING CHANGE: removed the deprecated Foo() function'
        )
        $entry = New-ChangelogEntry -Version '2.0.0' -Messages $messages -Date '2026-06-30'
    }

    It 'includes a version/date heading' {
        $entry | Should -Match '## \[2\.0\.0\] - 2026-06-30'
    }

    It 'groups breaking changes under their own section' {
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match '- redesign public API surface'
    }

    It 'groups fixes under their own section' {
        $entry | Should -Match '### Fixes'
        $entry | Should -Match '- clean up obsolete code paths'
    }

    It 'omits empty sections' {
        $patchOnlyEntry = New-ChangelogEntry -Version '1.0.1' -Messages @('fix: a bug') -Date '2026-06-30'
        $patchOnlyEntry | Should -Not -Match '### Features'
        $patchOnlyEntry | Should -Not -Match '### Breaking Changes'
    }
}

Describe 'Update-VersionFile' {

    Context 'Plain text VERSION file' {
        It 'overwrites the file with the new version' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "VERSION-$(Get-Random)"
            Set-Content -Path $tempFile -Value '1.0.0' -NoNewline
            try {
                Update-VersionFile -Path $tempFile -NewVersion '1.1.0'
                (Get-Content -Path $tempFile -Raw).Trim() | Should -Be '1.1.0'
            } finally {
                Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'package.json file' {
        It 'updates only the version field, preserving the rest of the file' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "package-$(Get-Random).json"
            '{
  "name": "demo",
  "version": "1.0.0",
  "private": true
}
' | Set-Content -Path $tempFile
            try {
                Update-VersionFile -Path $tempFile -NewVersion '1.1.0'
                $json = Get-Content -Path $tempFile -Raw | ConvertFrom-Json
                $json.version | Should -Be '1.1.0'
                $json.name | Should -Be 'demo'
                $json.private | Should -Be $true
            } finally {
                Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Missing file' {
        It 'throws a meaningful error' {
            { Update-VersionFile -Path '/nonexistent/VERSION' -NewVersion '1.0.0' } | Should -Throw '*not found*'
        }
    }
}

Describe 'Update-ChangelogFile' {

    It 'creates the changelog file with a title when it does not exist' {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "CHANGELOG-$(Get-Random).md"
        try {
            Update-ChangelogFile -Path $tempFile -Entry "## [1.0.0] - 2026-06-30`n`n- first release"
            $content = Get-Content -Path $tempFile -Raw
            $content | Should -Match '# Changelog'
            $content | Should -Match '## \[1\.0\.0\] - 2026-06-30'
        } finally {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }
    }

    It 'prepends new entries above existing ones' {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "CHANGELOG-$(Get-Random).md"
        try {
            Update-ChangelogFile -Path $tempFile -Entry '## [1.0.0] - 2026-06-30

- first release'
            Update-ChangelogFile -Path $tempFile -Entry '## [1.1.0] - 2026-07-01

- second release'
            $content = Get-Content -Path $tempFile -Raw
            $content.IndexOf('1.1.0') | Should -BeLessThan $content.IndexOf('1.0.0')
        } finally {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-VersionBump' {

    BeforeEach {
        $script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) "vb-$(Get-Random)"
        New-Item -ItemType Directory -Path $workDir | Out-Null
        $script:versionFile = Join-Path $workDir 'VERSION'
        $script:changelogFile = Join-Path $workDir 'CHANGELOG.md'
        Set-Content -Path $versionFile -Value '1.0.0' -NoNewline
    }

    AfterEach {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'bumps the version file and writes a changelog entry end-to-end for a feat commit' {
        $commitLog = Join-Path $FixturesPath 'commits-minor.log'
        $result = Invoke-VersionBump -VersionFilePath $versionFile -CommitLogPath $commitLog -ChangelogFilePath $changelogFile -Date '2026-06-30'

        $result.OldVersion | Should -Be '1.0.0'
        $result.NewVersion | Should -Be '1.1.0'
        $result.BumpType | Should -Be 'Minor'

        (Get-Content -Path $versionFile -Raw).Trim() | Should -Be '1.1.0'
        (Get-Content -Path $changelogFile -Raw) | Should -Match '## \[1\.1\.0\] - 2026-06-30'
    }

    It 'throws a meaningful error when there are no relevant commits' {
        $commitLog = Join-Path $FixturesPath 'commits-none.log'
        { Invoke-VersionBump -VersionFilePath $versionFile -CommitLogPath $commitLog -ChangelogFilePath $changelogFile -Date '2026-06-30' } |
            Should -Throw '*no version-relevant*'
    }
}
