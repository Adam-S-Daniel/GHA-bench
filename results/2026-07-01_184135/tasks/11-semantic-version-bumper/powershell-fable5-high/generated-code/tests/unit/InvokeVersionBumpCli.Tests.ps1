<#
.SYNOPSIS
    Tests for the CLI entry point src/Invoke-VersionBump.ps1 (the script
    the GitHub Actions workflow invokes).
#>

BeforeAll {
    $script:CliScript = Join-Path $PSScriptRoot '..' '..' 'src' 'Invoke-VersionBump.ps1'
    $script:FixtureDir = Join-Path $PSScriptRoot '..' '..' 'fixtures'
}

Describe 'Invoke-VersionBump.ps1 CLI' {
    BeforeEach {
        $script:workDir = Join-Path ([IO.Path]::GetTempPath()) "svb-cli-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Copy-Item (Join-Path $FixtureDir 'version-files' 'VERSION') $workDir
    }
    AfterEach {
        Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    }

    It 'prints the new version and exits 0 on success' {
        $out = & pwsh -NoProfile -File $CliScript `
            -VersionFile (Join-Path $workDir 'VERSION') `
            -CommitLogFile (Join-Path $FixtureDir 'commit-logs' 'feat.txt') `
            -ChangelogFile (Join-Path $workDir 'CHANGELOG.md')
        $LASTEXITCODE | Should -Be 0
        $out | Should -Contain '1.2.0'
    }

    It 'exits 1 with a meaningful error when the version file is missing' {
        $out = & pwsh -NoProfile -File $CliScript `
            -VersionFile (Join-Path $workDir 'nope') `
            -CommitLogFile (Join-Path $FixtureDir 'commit-logs' 'feat.txt') `
            -ChangelogFile (Join-Path $workDir 'CHANGELOG.md') 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out | Out-String) | Should -Match 'Version file not found'
    }
}
