# LicenseChecker.Tests.ps1
# Pester tests for the dependency license checker.
# Developed red/green using TDD: each Describe block was written as a failing
# test first, then the minimum implementation was added to make it pass.

BeforeAll {
    # Resolve the module relative to this test file so tests run from any CWD.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/LicenseChecker.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertFrom-DependencyManifest (package.json)' {

    It 'extracts dependency names and versions from a package.json' {
        $json = @'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "4.17.21"
  },
  "devDependencies": {
    "jest": "~29.5.0"
  }
}
'@
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value $json

        $result = ConvertFrom-DependencyManifest -Path $path

        $result | Should -HaveCount 3
        ($result | Where-Object Name -eq 'express').Version | Should -Be '^4.18.2'
        ($result | Where-Object Name -eq 'lodash').Version  | Should -Be '4.17.21'
        ($result | Where-Object Name -eq 'jest').Version    | Should -Be '~29.5.0'
    }

    It 'returns an empty result when there are no dependencies' {
        $json = '{ "name": "empty", "version": "1.0.0" }'
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value $json
        $result = @(ConvertFrom-DependencyManifest -Path $path)
        $result | Should -HaveCount 0
    }

    It 'throws a meaningful error for invalid JSON' {
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value '{ this is not json'
        { ConvertFrom-DependencyManifest -Path $path } |
            Should -Throw -ExpectedMessage '*Failed to parse package.json*'
    }

    It 'throws a meaningful error when the file does not exist' {
        { ConvertFrom-DependencyManifest -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw -ExpectedMessage '*Manifest file not found*'
    }
}

Describe 'ConvertFrom-DependencyManifest (requirements.txt)' {

    It 'extracts names and versions from a requirements.txt' {
        $txt = @'
# A comment line that should be ignored
requests==2.31.0
flask>=2.0.0

django~=4.2
no-version-pkg
'@
        $path = Join-Path $TestDrive 'requirements.txt'
        Set-Content -Path $path -Value $txt

        $result = ConvertFrom-DependencyManifest -Path $path

        $result | Should -HaveCount 4
        ($result | Where-Object Name -eq 'requests').Version | Should -Be '==2.31.0'
        ($result | Where-Object Name -eq 'flask').Version    | Should -Be '>=2.0.0'
        ($result | Where-Object Name -eq 'django').Version   | Should -Be '~=4.2'
        ($result | Where-Object Name -eq 'no-version-pkg').Version | Should -Be ''
    }

    It 'throws for an unsupported manifest type' {
        $path = Join-Path $TestDrive 'Gemfile'
        Set-Content -Path $path -Value 'gem "rails"'
        { ConvertFrom-DependencyManifest -Path $path } |
            Should -Throw -ExpectedMessage '*Unsupported manifest type*'
    }
}

Describe 'Get-DependencyLicense' {

    It 'returns the license string for a package present in the database' {
        $db = @{ express = 'MIT'; lodash = 'MIT' } | ConvertTo-Json
        $path = Join-Path $TestDrive 'license-db.json'
        Set-Content -Path $path -Value $db

        Get-DependencyLicense -Name 'express' -DatabasePath $path | Should -Be 'MIT'
    }

    It 'returns $null when the package is not in the database' {
        $db = @{ express = 'MIT' } | ConvertTo-Json
        $path = Join-Path $TestDrive 'license-db.json'
        Set-Content -Path $path -Value $db

        Get-DependencyLicense -Name 'ghost-pkg' -DatabasePath $path | Should -BeNullOrEmpty
    }
}

Describe 'Get-LicenseStatus' {

    BeforeAll {
        $script:config = [PSCustomObject]@{
            allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            deny  = @('GPL-3.0', 'AGPL-3.0')
        }
    }

    It 'classifies an allow-listed license as approved' {
        Get-LicenseStatus -License 'MIT' -Config $script:config | Should -Be 'approved'
    }

    It 'classifies a deny-listed license as denied' {
        Get-LicenseStatus -License 'GPL-3.0' -Config $script:config | Should -Be 'denied'
    }

    It 'classifies a license on neither list as unknown' {
        Get-LicenseStatus -License 'WTFPL' -Config $script:config | Should -Be 'unknown'
    }

    It 'classifies a missing license ($null) as unknown' {
        Get-LicenseStatus -License $null -Config $script:config | Should -Be 'unknown'
    }

    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit' -Config $script:config | Should -Be 'approved'
    }
}

Describe 'New-ComplianceReport' {

    BeforeAll {
        $script:config = [PSCustomObject]@{
            allow = @('MIT', 'Apache-2.0')
            deny  = @('GPL-3.0')
        }
    }

    It 'produces one report row per dependency with name, version, license and status' {
        $deps = @(
            [PSCustomObject]@{ Name = 'express';  Version = '4.18.2' }
            [PSCustomObject]@{ Name = 'gpl-lib';  Version = '1.0.0'  }
            [PSCustomObject]@{ Name = 'mystery';  Version = '2.0.0'  }
        )

        # Mock the license lookup so the test is deterministic and offline.
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            switch ($Name) {
                'express' { 'MIT' }
                'gpl-lib' { 'GPL-3.0' }
                default   { $null }
            }
        }

        $report = New-ComplianceReport -Dependencies $deps -Config $script:config -DatabasePath 'unused'

        $report | Should -HaveCount 3
        ($report | Where-Object Name -eq 'express').License | Should -Be 'MIT'
        ($report | Where-Object Name -eq 'express').Status  | Should -Be 'approved'
        ($report | Where-Object Name -eq 'gpl-lib').Status  | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery').Status  | Should -Be 'unknown'
        ($report | Where-Object Name -eq 'mystery').License | Should -Be 'UNKNOWN'

        # Verify the (mocked) license lookup was actually invoked once per dependency.
        Should -Invoke -ModuleName LicenseChecker Get-DependencyLicense -Times 3
    }
}

Describe 'Format-ComplianceReport' {

    It 'renders deterministic per-dependency lines and an exact summary' {
        $report = @(
            [PSCustomObject]@{ Name = 'express'; Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
            [PSCustomObject]@{ Name = 'gpl-lib'; Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied'   }
            [PSCustomObject]@{ Name = 'mystery'; Version = '2.0.0';  License = 'UNKNOWN'; Status = 'unknown'  }
        )

        $text = Format-ComplianceReport -Report $report

        $text | Should -Match '\[APPROVED\] express@4.18.2 -> MIT'
        $text | Should -Match '\[DENIED\] gpl-lib@1.0.0 -> GPL-3.0'
        $text | Should -Match '\[UNKNOWN\] mystery@2.0.0 -> UNKNOWN'
        $text | Should -Match 'SUMMARY: total=3 approved=1 denied=1 unknown=1'
    }

    It 'reports an all-clear summary when every dependency is approved' {
        $report = @(
            [PSCustomObject]@{ Name = 'a'; Version = '1.0.0'; License = 'MIT'; Status = 'approved' }
        )
        $text = Format-ComplianceReport -Report $report
        $text | Should -Match 'SUMMARY: total=1 approved=1 denied=0 unknown=0'
        $text | Should -Match 'RESULT: COMPLIANT'
    }

    It 'reports a non-compliant result when any dependency is denied' {
        $report = @(
            [PSCustomObject]@{ Name = 'a'; Version = '1.0.0'; License = 'GPL-3.0'; Status = 'denied' }
        )
        $text = Format-ComplianceReport -Report $report
        $text | Should -Match 'RESULT: NON-COMPLIANT'
    }
}

Describe 'Invoke-LicenseCheck.ps1 (end-to-end CLI)' {

    BeforeAll {
        $script:Cli = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-LicenseCheck.ps1'

        # Build a self-contained fixture set in the test drive.
        $script:fixtureDir = Join-Path $TestDrive 'cli'
        New-Item -ItemType Directory -Path $script:fixtureDir | Out-Null

        Set-Content -Path (Join-Path $script:fixtureDir 'package.json') -Value (@'
{
  "name": "cli-demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2",
    "gpl-lib": "1.0.0",
    "mystery-pkg": "2.0.0"
  }
}
'@)

        Set-Content -Path (Join-Path $script:fixtureDir 'license-config.json') -Value (@'
{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"] }
'@)

        Set-Content -Path (Join-Path $script:fixtureDir 'license-db.json') -Value (@'
{ "express": "MIT", "gpl-lib": "GPL-3.0" }
'@)
    }

    It 'prints an exact report and exits 0 in report mode' {
        $out = & pwsh -NoProfile -File $script:Cli `
            -ManifestPath (Join-Path $script:fixtureDir 'package.json') `
            -ConfigPath   (Join-Path $script:fixtureDir 'license-config.json') `
            -LicenseDbPath (Join-Path $script:fixtureDir 'license-db.json') 2>&1
        $exit = $LASTEXITCODE
        $text = ($out | Out-String)

        $exit | Should -Be 0
        $text | Should -Match '\[APPROVED\] express@4.18.2 -> MIT'
        $text | Should -Match '\[DENIED\] gpl-lib@1.0.0 -> GPL-3.0'
        $text | Should -Match '\[UNKNOWN\] mystery-pkg@2.0.0 -> UNKNOWN'
        $text | Should -Match 'SUMMARY: total=3 approved=1 denied=1 unknown=1'
        $text | Should -Match 'RESULT: NON-COMPLIANT'
    }

    It 'exits 1 under -FailOnViolation when a denied license is present' {
        & pwsh -NoProfile -File $script:Cli `
            -ManifestPath (Join-Path $script:fixtureDir 'package.json') `
            -ConfigPath   (Join-Path $script:fixtureDir 'license-config.json') `
            -LicenseDbPath (Join-Path $script:fixtureDir 'license-db.json') `
            -FailOnViolation *> $null
        $LASTEXITCODE | Should -Be 1
    }

    It 'auto-discovers a manifest when given a directory' {
        $out = & pwsh -NoProfile -File $script:Cli `
            -ManifestPath $script:fixtureDir `
            -ConfigPath   (Join-Path $script:fixtureDir 'license-config.json') `
            -LicenseDbPath (Join-Path $script:fixtureDir 'license-db.json') 2>&1
        ($out | Out-String) | Should -Match 'SUMMARY: total=3 approved=1 denied=1 unknown=1'
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 2 with a clear error when the manifest is missing' {
        $out = & pwsh -NoProfile -File $script:Cli `
            -ManifestPath (Join-Path $script:fixtureDir 'does-not-exist.json') `
            -ConfigPath   (Join-Path $script:fixtureDir 'license-config.json') `
            -LicenseDbPath (Join-Path $script:fixtureDir 'license-db.json') 2>&1
        $LASTEXITCODE | Should -Be 2
        ($out | Out-String) | Should -Match 'ERROR'
    }
}
