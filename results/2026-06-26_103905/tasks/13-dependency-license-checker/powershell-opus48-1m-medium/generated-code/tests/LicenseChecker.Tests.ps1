# Pester tests for the Dependency License Checker module.
# Written test-first (red/green TDD). Each Describe block corresponds to a
# distinct piece of functionality that was driven out by a failing test.

BeforeAll {
    # Import the module under test. Resolve path relative to this test file so
    # the suite runs from any working directory.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $script:ModulePath -Force

    $script:FixtureDir = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-Dependencies (manifest parsing)' {

    Context 'package.json' {
        It 'extracts dependency names and versions from a package.json' {
            $manifest = Join-Path $script:FixtureDir 'package.json'
            $deps = Get-Dependencies -Path $manifest

            $deps | Should -Not -BeNullOrEmpty
            ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
            ($deps | Where-Object Name -eq 'lodash').Version    | Should -Be '4.17.21'
        }

        It 'includes devDependencies as well as runtime dependencies' {
            $manifest = Join-Path $script:FixtureDir 'package.json'
            $deps = Get-Dependencies -Path $manifest
            ($deps | Where-Object Name -eq 'jest').Version | Should -Be '29.7.0'
        }

        It 'strips semver range prefixes (^ ~ >=) from versions' {
            $manifest = Join-Path $script:FixtureDir 'package.json'
            $deps = Get-Dependencies -Path $manifest
            # express is declared as "^4.18.2" in the fixture
            ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
        }
    }

    Context 'requirements.txt' {
        It 'extracts dependency names and pinned versions from requirements.txt' {
            $manifest = Join-Path $script:FixtureDir 'requirements.txt'
            $deps = Get-Dependencies -Path $manifest
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '3.0.0'
        }

        It 'ignores comments and blank lines' {
            $manifest = Join-Path $script:FixtureDir 'requirements.txt'
            $deps = Get-Dependencies -Path $manifest
            $deps.Name | Should -Not -Contain '# this is a comment'
            $deps.Name | Should -Not -Contain ''
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-Dependencies -Path (Join-Path $script:FixtureDir 'nope.json') } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'pom.xml'
            Set-Content -Path $tmp -Value '<project/>'
            { Get-Dependencies -Path $tmp } | Should -Throw -ExpectedMessage '*Unsupported*'
            Remove-Item $tmp -Force
        }
    }
}

Describe 'Get-LicenseConfig (allow/deny list loading)' {
    It 'loads allow and deny lists from a JSON config file' {
        $cfg = Get-LicenseConfig -Path (Join-Path $script:FixtureDir '..' 'config' 'license-config.json')
        $cfg.Allow | Should -Contain 'MIT'
        $cfg.Deny  | Should -Contain 'GPL-3.0'
    }

    It 'throws when the config file is missing' {
        { Get-LicenseConfig -Path 'does-not-exist.json' } | Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Test-LicenseStatus (compliance decision)' {
    BeforeAll {
        $script:Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $script:Deny  = @('GPL-3.0', 'AGPL-3.0')
    }

    It 'returns "approved" for a license on the allow-list' {
        Test-LicenseStatus -License 'MIT' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'approved'
    }

    It 'returns "denied" for a license on the deny-list' {
        Test-LicenseStatus -License 'GPL-3.0' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'denied'
    }

    It 'returns "unknown" for a license on neither list' {
        Test-LicenseStatus -License 'WTFPL' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'unknown'
    }

    It 'returns "unknown" when the license is null or empty' {
        Test-LicenseStatus -License '' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'unknown'
    }

    It 'treats deny-list as taking precedence over allow-list' {
        # A license that somehow appears on both lists must be denied (fail-safe).
        Test-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') |
            Should -Be 'denied'
    }
}

Describe 'Get-DependencyLicense (mockable license lookup)' {
    It 'resolves a license from the provided lookup database' {
        $db = @{ 'lodash' = 'MIT'; 'left-pad' = 'WTFPL' }
        Get-DependencyLicense -Name 'lodash' -Version '4.17.21' -Database $db | Should -Be 'MIT'
    }

    It 'returns UNKNOWN when the dependency is absent from the database' {
        $db = @{ 'lodash' = 'MIT' }
        Get-DependencyLicense -Name 'mystery' -Version '1.0.0' -Database $db | Should -Be 'UNKNOWN'
    }
}

Describe 'New-ComplianceReport (end-to-end orchestration)' {
    BeforeAll {
        $script:Manifest = Join-Path $script:FixtureDir 'package.json'
        $script:Config   = Join-Path $script:FixtureDir '..' 'config' 'license-config.json'
    }

    It 'produces one report row per dependency with a status' {
        # Mock Get-DependencyLicense so the test is deterministic and offline.
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            switch ($Name) {
                'lodash'   { 'MIT' }
                'express'  { 'MIT' }
                'left-pad' { 'GPL-3.0' }
                'jest'     { 'SomethingWeird' }
                default    { 'UNKNOWN' }
            }
        }

        $report = New-ComplianceReport -ManifestPath $script:Manifest -ConfigPath $script:Config

        ($report | Where-Object Name -eq 'lodash').Status   | Should -Be 'approved'
        ($report | Where-Object Name -eq 'left-pad').Status | Should -Be 'denied'
        ($report | Where-Object Name -eq 'jest').Status     | Should -Be 'unknown'
        $report.Count | Should -BeGreaterThan 0
    }

    It 'attaches the resolved license to each row' {
        Mock -ModuleName LicenseChecker Get-DependencyLicense { 'MIT' }
        $report = New-ComplianceReport -ManifestPath $script:Manifest -ConfigPath $script:Config
        ($report | Where-Object Name -eq 'lodash').License | Should -Be 'MIT'
        $report | ForEach-Object { $_.Status | Should -Be 'approved' }
    }
}

Describe 'Format-ComplianceReport (rendering + summary)' {
    It 'renders a human-readable report containing a summary line' {
        $rows = @(
            [pscustomobject]@{ Name = 'a'; Version = '1.0'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'b'; Version = '2.0'; License = 'GPL-3.0'; Status = 'denied' }
            [pscustomobject]@{ Name = 'c'; Version = '3.0'; License = 'WTFPL';   Status = 'unknown' }
        )
        $text = Format-ComplianceReport -Report $rows | Out-String
        $text | Should -Match 'Approved:\s*1'
        $text | Should -Match 'Denied:\s*1'
        $text | Should -Match 'Unknown:\s*1'
        $text | Should -Match 'GPL-3.0'
    }
}
