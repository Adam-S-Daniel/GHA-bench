#requires -Modules Pester
<#
    LicenseChecker.Tests.ps1

    Pester v5 unit tests for the dependency license compliance checker.
    These tests are written FIRST (red/green TDD) and drive the design of
    the functions exported from ../LicenseChecker.psm1.

    The tests are deliberately self-contained and offline: the "license
    lookup" is mocked / fed from an in-memory database so the suite is
    deterministic and runs inside an isolated CI container with no network.
#>

BeforeAll {
    # Resolve paths relative to this test file so the suite works from any CWD
    # (locally and inside the GitHub Actions / act container).
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'LicenseChecker.psm1'
    $script:FixtureDir = Join-Path $PSScriptRoot '..' 'fixtures'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-DependencyList' {

    Context 'package.json manifests' {

        It 'returns every dependency and devDependency with its version' {
            $manifest = Join-Path $script:FixtureDir 'package.json'

            $deps = Get-DependencyList -ManifestPath $manifest

            # express, lodash (dependencies) + jest (devDependencies) = 3
            $deps.Count | Should -Be 3

            $express = $deps | Where-Object Name -eq 'express'
            $express.Version | Should -Be '^4.18.2'

            ($deps | Where-Object Name -eq 'jest').Version | Should -Be '~29.0.0'

            # Names should come back as a flat set we can assert against.
            ($deps.Name | Sort-Object) | Should -Be @('express', 'jest', 'lodash')
        }
    }

    Context 'requirements.txt manifests' {

        It 'parses pinned, ranged and extras-qualified requirements and ignores comments/blanks' {
            $manifest = Join-Path $script:FixtureDir 'requirements.txt'

            $deps = Get-DependencyList -ManifestPath $manifest

            # requests, flask, numpy, click = 4 (comments + blank lines skipped)
            $deps.Count | Should -Be 4

            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '2.0.0'
            ($deps | Where-Object Name -eq 'numpy').Version    | Should -Be '1.26.0'

            # extras "[extras]" and the environment marker / inline comment
            # must be stripped from the package name and version.
            ($deps | Where-Object Name -eq 'click').Version    | Should -Be '8.1.7'

            ($deps.Name | Sort-Object) | Should -Be @('click', 'flask', 'numpy', 'requests')
        }
    }

    Context 'unsupported / missing manifests' {

        It 'throws a meaningful error when the file does not exist' {
            { Get-DependencyList -ManifestPath 'does-not-exist.json' } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'pom.xml'
            Set-Content -LiteralPath $tmp -Value '<project/>'
            try {
                { Get-DependencyList -ManifestPath $tmp } |
                    Should -Throw -ExpectedMessage '*Unsupported manifest*'
            }
            finally {
                Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-DependencyLicense' {

    BeforeAll {
        # A small in-memory "mock" license database. In production this would be
        # populated from a registry query; for tests it makes lookups offline
        # and deterministic.
        $script:Db = @{
            'express' = 'MIT'
            'gpl-tool' = 'GPL-3.0'
        }
    }

    It 'returns the license recorded in the database' {
        Get-DependencyLicense -Name 'express' -LicenseDatabase $script:Db | Should -Be 'MIT'
    }

    It 'is case-insensitive on the package name' {
        Get-DependencyLicense -Name 'Express' -LicenseDatabase $script:Db | Should -Be 'MIT'
    }

    It 'returns "Unknown" when the package is not in the database' {
        Get-DependencyLicense -Name 'mystery' -LicenseDatabase $script:Db | Should -Be 'Unknown'
    }

    It 'returns "Unknown" when no database is supplied' {
        Get-DependencyLicense -Name 'express' | Should -Be 'Unknown'
    }
}

Describe 'Test-LicenseStatus' {

    BeforeAll {
        $script:Config = [pscustomobject]@{
            AllowList = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            DenyList  = @('GPL-3.0', 'AGPL-3.0')
        }
    }

    It 'classifies an allow-listed license as Approved' {
        Test-LicenseStatus -License 'MIT' -Config $script:Config | Should -Be 'Approved'
    }

    It 'classifies a deny-listed license as Denied' {
        Test-LicenseStatus -License 'GPL-3.0' -Config $script:Config | Should -Be 'Denied'
    }

    It 'matches license names case-insensitively' {
        Test-LicenseStatus -License 'mit' -Config $script:Config | Should -Be 'Approved'
    }

    It 'classifies a license that appears on neither list as Unknown' {
        Test-LicenseStatus -License 'MPL-2.0' -Config $script:Config | Should -Be 'Unknown'
    }

    It 'classifies the literal "Unknown" license as Unknown' {
        Test-LicenseStatus -License 'Unknown' -Config $script:Config | Should -Be 'Unknown'
    }

    It 'classifies an empty / null license as Unknown' {
        Test-LicenseStatus -License '' -Config $script:Config | Should -Be 'Unknown'
    }

    It 'gives the deny-list precedence when a license is on both lists' {
        $conflict = [pscustomobject]@{
            AllowList = @('MIT')
            DenyList  = @('MIT')
        }
        Test-LicenseStatus -License 'MIT' -Config $conflict | Should -Be 'Denied'
    }
}

Describe 'New-ComplianceReport' {

    BeforeAll {
        $script:Config = [pscustomobject]@{
            AllowList = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            DenyList  = @('GPL-3.0', 'GPL-2.0', 'AGPL-3.0')
        }
        $script:Db = @{
            'express'  = 'MIT'      # approved
            'gpl-tool' = 'GPL-3.0'  # denied
            # 'jest' deliberately absent -> Unknown
        }
        $script:Manifest = Join-Path $script:FixtureDir 'package.json'
    }

    It 'produces one report item per dependency with name, version, license and status' {
        $report = New-ComplianceReport -ManifestPath $script:Manifest -Config $script:Config -LicenseDatabase $script:Db

        $report.Items.Count | Should -Be 3

        $express = $report.Items | Where-Object Name -eq 'express'
        $express.Version | Should -Be '^4.18.2'
        $express.License | Should -Be 'MIT'
        $express.Status  | Should -Be 'Approved'
    }

    It 'computes an accurate summary of Approved/Denied/Unknown counts' {
        # Use a manifest that exercises all three statuses.
        $mixed = Join-Path ([System.IO.Path]::GetTempPath()) "mixed-$([System.Guid]::NewGuid().ToString('N')).json"
        @'
{
  "dependencies": { "express": "1.0.0", "gpl-tool": "2.0.0" },
  "devDependencies": { "jest": "3.0.0" }
}
'@ | Set-Content -LiteralPath $mixed
        try {
            $report = New-ComplianceReport -ManifestPath $mixed -Config $script:Config -LicenseDatabase $script:Db

            $report.Summary.Total    | Should -Be 3
            $report.Summary.Approved | Should -Be 1   # express / MIT
            $report.Summary.Denied   | Should -Be 1   # gpl-tool / GPL-3.0
            $report.Summary.Unknown  | Should -Be 1   # jest / not in db
        }
        finally {
            Remove-Item -LiteralPath $mixed -ErrorAction SilentlyContinue
        }
    }

    It 'uses the (mocked) license lookup once per dependency' {
        # Demonstrates mocking the license lookup seam: every dependency is
        # forced to resolve to MIT, so the whole manifest becomes Approved.
        Mock -ModuleName LicenseChecker Get-DependencyLicense { 'MIT' }

        $report = New-ComplianceReport -ManifestPath $script:Manifest -Config $script:Config

        $report.Summary.Total    | Should -Be 3
        $report.Summary.Approved | Should -Be 3
        ($report.Items | Where-Object License -ne 'MIT') | Should -BeNullOrEmpty

        Should -Invoke -ModuleName LicenseChecker Get-DependencyLicense -Times 3 -Exactly
    }
}

Describe 'Format-ComplianceReport' {

    BeforeAll {
        $script:Report = [pscustomobject]@{
            Manifest = 'demo/package.json'
            Items    = @(
                [pscustomobject]@{ Name = 'express';  Version = '4.18.2'; License = 'MIT';     Status = 'Approved' }
                [pscustomobject]@{ Name = 'gpl-tool'; Version = '1.0.0';  License = 'GPL-3.0'; Status = 'Denied'   }
                [pscustomobject]@{ Name = 'mystery';  Version = '2.0.0';  License = 'Unknown'; Status = 'Unknown'  }
            )
            Summary  = [pscustomobject]@{ Total = 3; Approved = 1; Denied = 1; Unknown = 1 }
        }
    }

    It 'emits a machine-parseable line per dependency' {
        $lines = Format-ComplianceReport -Report $script:Report

        ($lines | Where-Object { $_ -match '^DEP \| express \| 4\.18\.2 \| MIT \| Approved$' }) |
            Should -Not -BeNullOrEmpty
        ($lines | Where-Object { $_ -match '^DEP \| gpl-tool \| 1\.0\.0 \| GPL-3\.0 \| Denied$' }) |
            Should -Not -BeNullOrEmpty
    }

    It 'emits an exact SUMMARY line with the four counts' {
        $lines = Format-ComplianceReport -Report $script:Report

        ($lines | Where-Object { $_ -eq 'SUMMARY | Total: 3 | Approved: 1 | Denied: 1 | Unknown: 1' }) |
            Should -Not -BeNullOrEmpty
    }

    It 'reports overall RESULT as FAIL when denied licenses are present' {
        $lines = Format-ComplianceReport -Report $script:Report
        ($lines | Where-Object { $_ -eq 'RESULT: FAIL' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports overall RESULT as PASS when nothing is denied' {
        $clean = [pscustomobject]@{
            Manifest = 'demo/package.json'
            Items    = @(
                [pscustomobject]@{ Name = 'express'; Version = '4.18.2'; License = 'MIT'; Status = 'Approved' }
            )
            Summary  = [pscustomobject]@{ Total = 1; Approved = 1; Denied = 0; Unknown = 0 }
        }
        $lines = Format-ComplianceReport -Report $clean
        ($lines | Where-Object { $_ -eq 'RESULT: PASS' }) | Should -Not -BeNullOrEmpty
    }
}
