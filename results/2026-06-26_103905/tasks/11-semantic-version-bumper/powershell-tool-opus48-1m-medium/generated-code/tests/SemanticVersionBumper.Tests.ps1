# Unit tests for the Semantic Version Bumper module.
# Developed using red/green TDD: each Describe block was written as a failing
# test first, then the minimum implementation was added in src/SemanticVersionBumper.psm1.

BeforeAll {
    # Import the module under test relative to this test file.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'SemanticVersionBumper.psm1'
    Import-Module $script:ModulePath -Force

    # A scratch directory for fixtures created/torn down per run.
    $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("svb-test-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TmpRoot) { Remove-Item $script:TmpRoot -Recurse -Force }
}

Describe 'Get-CurrentVersion' {

    It 'reads a plain semantic version from a version.txt file' {
        $f = Join-Path $script:TmpRoot 'version.txt'
        Set-Content -Path $f -Value '1.4.2'
        (Get-CurrentVersion -Path $f) | Should -Be '1.4.2'
    }

    It 'reads the version field from a package.json file' {
        $f = Join-Path $script:TmpRoot 'package.json'
        @{ name = 'demo'; version = '2.3.4' } | ConvertTo-Json | Set-Content -Path $f
        (Get-CurrentVersion -Path $f) | Should -Be '2.3.4'
    }

    It 'ignores leading "v" prefixes and surrounding whitespace' {
        $f = Join-Path $script:TmpRoot 'vprefixed.txt'
        Set-Content -Path $f -Value '  v0.9.1  '
        (Get-CurrentVersion -Path $f) | Should -Be '0.9.1'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-CurrentVersion -Path (Join-Path $script:TmpRoot 'nope.txt') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error when the version string is not semantic' {
        $f = Join-Path $script:TmpRoot 'bad.txt'
        Set-Content -Path $f -Value 'not-a-version'
        { Get-CurrentVersion -Path $f } | Should -Throw -ExpectedMessage '*not a valid semantic version*'
    }
}

Describe 'Get-BumpType' {

    It 'returns "minor" for a feat commit' {
        Get-BumpType -Commits @('feat: add login page') | Should -Be 'minor'
    }

    It 'returns "patch" for a fix commit' {
        Get-BumpType -Commits @('fix: correct null check') | Should -Be 'patch'
    }

    It 'returns "major" for a commit with a "!" breaking marker' {
        Get-BumpType -Commits @('feat!: drop node 14 support') | Should -Be 'major'
    }

    It 'returns "major" for a BREAKING CHANGE footer' {
        $msg = "feat: new api`n`nBREAKING CHANGE: removes old endpoint"
        Get-BumpType -Commits @($msg) | Should -Be 'major'
    }

    It 'returns "none" when no commit triggers a bump' {
        Get-BumpType -Commits @('docs: update readme', 'chore: bump deps') | Should -Be 'none'
    }

    It 'returns the highest precedence bump across mixed commits (major wins)' {
        Get-BumpType -Commits @('fix: a', 'feat: b', 'refactor!: c') | Should -Be 'major'
    }

    It 'returns "minor" when feat outranks fix' {
        Get-BumpType -Commits @('fix: a', 'feat: b') | Should -Be 'minor'
    }
}

Describe 'Step-Version' {

    It 'increments the major and resets minor/patch' {
        Step-Version -Version '1.4.2' -BumpType 'major' | Should -Be '2.0.0'
    }

    It 'increments the minor and resets patch' {
        Step-Version -Version '1.4.2' -BumpType 'minor' | Should -Be '1.5.0'
    }

    It 'increments the patch only' {
        Step-Version -Version '1.4.2' -BumpType 'patch' | Should -Be '1.4.3'
    }

    It 'returns the same version when bump type is none' {
        Step-Version -Version '1.4.2' -BumpType 'none' | Should -Be '1.4.2'
    }

    It 'throws on an invalid bump type' {
        { Step-Version -Version '1.0.0' -BumpType 'huge' } | Should -Throw
    }
}

Describe 'Set-CurrentVersion' {

    It 'writes a plain version file back' {
        $f = Join-Path $script:TmpRoot 'set-plain.txt'
        Set-Content -Path $f -Value '1.0.0'
        Set-CurrentVersion -Path $f -Version '1.1.0'
        (Get-CurrentVersion -Path $f) | Should -Be '1.1.0'
    }

    It 'updates only the version field of package.json, preserving other fields' {
        $f = Join-Path $script:TmpRoot 'set-pkg.json'
        @{ name = 'demo'; version = '1.0.0'; private = $true } | ConvertTo-Json | Set-Content -Path $f
        Set-CurrentVersion -Path $f -Version '2.0.0'
        $obj = Get-Content $f -Raw | ConvertFrom-Json
        $obj.version | Should -Be '2.0.0'
        $obj.name    | Should -Be 'demo'
        $obj.private | Should -BeTrue
    }
}

Describe 'New-ChangelogEntry' {

    It 'renders a header with the version and groups commits by type' {
        $entry = New-ChangelogEntry -Version '1.2.0' -Commits @(
            'feat: add search',
            'fix: handle empty input',
            'chore: tidy'
        )
        $entry | Should -Match '## 1\.2\.0'
        $entry | Should -Match 'Features'
        $entry | Should -Match 'add search'
        $entry | Should -Match 'Bug Fixes'
        $entry | Should -Match 'handle empty input'
    }

    It 'includes a Breaking Changes section when present' {
        $entry = New-ChangelogEntry -Version '2.0.0' -Commits @('feat!: remove v1 api')
        $entry | Should -Match 'Breaking Changes'
        $entry | Should -Match 'remove v1 api'
    }
}

Describe 'Invoke-Bumper.ps1 (CLI orchestrator)' {

    BeforeAll {
        $script:Cli = Join-Path $PSScriptRoot '..' 'Invoke-Bumper.ps1'
    }

    BeforeEach {
        # Each case runs in its own isolated working dir.
        $script:WorkDir = Join-Path $script:TmpRoot ("cli-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    }

    It 'bumps a minor version from a feat commit and updates files + changelog' {
        $ver = Join-Path $script:WorkDir 'version.txt'
        $log = Join-Path $script:WorkDir 'commits.txt'
        Set-Content $ver '1.1.0'
        Set-Content $log 'feat: add a thing'

        $out = & $script:Cli -VersionPath $ver -CommitLogPath $log -ChangelogPath (Join-Path $script:WorkDir 'CHANGELOG.md')

        # The script must print a clear machine-parseable line.
        ($out -join "`n") | Should -Match 'NEW_VERSION=1\.2\.0'
        (Get-CurrentVersion -Path $ver) | Should -Be '1.2.0'
        (Get-Content (Join-Path $script:WorkDir 'CHANGELOG.md') -Raw) | Should -Match '## 1\.2\.0'
    }

    It 'bumps a major version from a breaking commit in package.json' {
        $ver = Join-Path $script:WorkDir 'package.json'
        $log = Join-Path $script:WorkDir 'commits.txt'
        @{ name = 'demo'; version = '3.4.5' } | ConvertTo-Json | Set-Content $ver
        Set-Content $log 'feat!: overhaul api'

        $out = & $script:Cli -VersionPath $ver -CommitLogPath $log -ChangelogPath (Join-Path $script:WorkDir 'CHANGELOG.md')
        ($out -join "`n") | Should -Match 'NEW_VERSION=4\.0\.0'
        (Get-CurrentVersion -Path $ver) | Should -Be '4.0.0'
    }

    It 'does not change the version when there are no bump-worthy commits' {
        $ver = Join-Path $script:WorkDir 'version.txt'
        $log = Join-Path $script:WorkDir 'commits.txt'
        Set-Content $ver '1.1.0'
        Set-Content $log "docs: tweak readme`nchore: deps"

        $out = & $script:Cli -VersionPath $ver -CommitLogPath $log -ChangelogPath (Join-Path $script:WorkDir 'CHANGELOG.md')
        ($out -join "`n") | Should -Match 'NEW_VERSION=1\.1\.0'
        (Get-CurrentVersion -Path $ver) | Should -Be '1.1.0'
    }

    It 'exits non-zero with a meaningful message when the version file is missing' {
        $log = Join-Path $script:WorkDir 'commits.txt'
        Set-Content $log 'feat: x'
        $err = & $script:Cli -VersionPath (Join-Path $script:WorkDir 'missing.txt') -CommitLogPath $log 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($err -join "`n") | Should -Match 'not found'
    }
}
