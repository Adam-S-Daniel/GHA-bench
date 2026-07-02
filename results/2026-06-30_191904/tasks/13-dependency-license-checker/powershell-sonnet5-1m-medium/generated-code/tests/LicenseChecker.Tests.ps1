<#
    Pester tests for LicenseChecker.psm1, developed red/green:
      1. Get-DependencyManifest parsing (package.json, requirements.txt, errors)
      2. Test-LicenseStatus classification (approved / denied / unknown)
      3. Get-PackageLicense (local database + mocked network fallback)
      4. New-ComplianceReport end-to-end wiring
      5. Format-ComplianceReport rendering

    These are executed inside the GitHub Actions workflow via `act`, per the
    task's "all tests run through the pipeline" requirement.
#>

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $moduleRoot 'LicenseChecker.psm1') -Force
    $fixturesPath = Join-Path $moduleRoot 'fixtures'
}

Describe 'Get-DependencyManifest' {

    Context 'package.json' {
        It 'extracts dependency names and stripped versions from dependencies and devDependencies' {
            $result = Get-DependencyManifest -Path (Join-Path $fixturesPath 'package.json')

            $result.Count | Should -Be 3
            ($result | Where-Object Name -eq 'lodash').Version | Should -Be '4.17.21'
            ($result | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
            ($result | Where-Object Name -eq 'gpl-lib').Version | Should -Be '1.0.0'
        }
    }

    Context 'requirements.txt' {
        It 'extracts pinned versions, range versions, and bare package names' {
            $result = Get-DependencyManifest -Path (Join-Path $fixturesPath 'requirements.txt')

            $result.Count | Should -Be 3
            ($result | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($result | Where-Object Name -eq 'flask').Version | Should -Be '2.0.0'
            ($result | Where-Object Name -eq 'left-pad').Version | Should -Be 'unknown'
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the manifest file does not exist' {
            { Get-DependencyManifest -Path (Join-Path $fixturesPath 'does-not-exist.json') } |
                Should -Throw '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest format' {
            $tempFile = Join-Path $TestDrive 'Gemfile.lock'
            Set-Content -Path $tempFile -Value 'gem "rails"'

            { Get-DependencyManifest -Path $tempFile } | Should -Throw '*Unsupported manifest format*'
        }
    }
}

Describe 'Test-LicenseStatus' {
    BeforeAll {
        $allow = @('MIT', 'Apache-2.0')
        $deny = @('GPL-3.0')
    }

    It 'returns Approved when the license is in the allow list' {
        Test-LicenseStatus -License 'MIT' -AllowList $allow -DenyList $deny | Should -Be 'Approved'
    }

    It 'returns Denied when the license is in the deny list' {
        Test-LicenseStatus -License 'GPL-3.0' -AllowList $allow -DenyList $deny | Should -Be 'Denied'
    }

    It 'returns Unknown when the license is in neither list' {
        Test-LicenseStatus -License 'WTFPL' -AllowList $allow -DenyList $deny | Should -Be 'Unknown'
    }

    It 'returns Unknown when the license is null or empty' {
        Test-LicenseStatus -License $null -AllowList $allow -DenyList $deny | Should -Be 'Unknown'
    }

    It 'prefers Denied when a license appears in both lists' {
        Test-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') | Should -Be 'Denied'
    }
}

Describe 'Get-PackageLicense' {

    Context 'with a local license database (offline mode)' {
        It 'returns the license from the database when the package is present' {
            $db = @{ lodash = 'MIT' }
            Get-PackageLicense -Name 'lodash' -Version '4.17.21' -LicenseDatabase $db | Should -Be 'MIT'
        }

        It 'returns null when the package is absent from the database' {
            $db = @{ lodash = 'MIT' }
            Get-PackageLicense -Name 'totally-unlisted-package' -Version '1.0.0' -LicenseDatabase $db | Should -BeNullOrEmpty
        }
    }

    Context 'without a database (network fallback, mocked)' {
        It 'delegates to Resolve-PackageLicense and returns its result' {
            Mock Resolve-PackageLicense { return 'ISC' } -ModuleName LicenseChecker

            $result = Get-PackageLicense -Name 'some-pkg' -Version '1.0.0'

            $result | Should -Be 'ISC'
            Should -Invoke Resolve-PackageLicense -ModuleName LicenseChecker -Times 1 -Exactly
        }
    }
}

Describe 'New-ComplianceReport' {
    It 'produces one row per dependency with the correct license and status' {
        $config = [PSCustomObject]@{
            allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            deny  = @('GPL-3.0')
        }
        $database = [PSCustomObject]@{
            lodash   = 'MIT'
            'gpl-lib' = 'GPL-3.0'
        }

        $report = New-ComplianceReport -ManifestPath (Join-Path $fixturesPath 'package.json') -Config $config -LicenseDatabase $database

        $report.Count | Should -Be 3
        ($report | Where-Object Name -eq 'lodash').Status | Should -Be 'Approved'
        ($report | Where-Object Name -eq 'gpl-lib').Status | Should -Be 'Denied'
        ($report | Where-Object Name -eq 'express').Status | Should -Be 'Unknown'
    }

    It 'throws a meaningful error when the config is missing allow/deny arrays' {
        $badConfig = [PSCustomObject]@{ allow = @('MIT') }

        { New-ComplianceReport -ManifestPath (Join-Path $fixturesPath 'package.json') -Config $badConfig -LicenseDatabase ([PSCustomObject]@{}) } |
            Should -Throw "*must contain*"
    }
}

Describe 'Format-ComplianceReport' {
    It 'renders a markdown table with a header row and one row per dependency' {
        $report = @(
            [PSCustomObject]@{ Name = 'lodash'; Version = '4.17.21'; License = 'MIT'; Status = 'Approved' }
        )

        $markdown = Format-ComplianceReport -Report $report

        $markdown | Should -Match '\| Package \| Version \| License \| Status \|'
        $markdown | Should -Match '\| lodash \| 4\.17\.21 \| MIT \| Approved \|'
    }

    It 'handles an empty report without error' {
        { Format-ComplianceReport -Report @() } | Should -Not -Throw
    }
}
