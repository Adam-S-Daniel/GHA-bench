#Requires -Modules Pester

<#
    TDD test suite for the dependency license checker.

    Written RED-first: every block below was authored before its
    corresponding implementation existed in LicenseChecker.psm1, run to
    confirm failure, then made to pass with the minimum code needed.
    Mocks stand in for the license lookup so tests never touch the
    network or a real license database.
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'LicenseChecker.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-ManifestDependency' {

    Context 'package.json manifests' {
        BeforeAll {
            $fixture = Join-Path $PSScriptRoot '..' 'fixtures' 'package-allowed.json'
        }

        It 'extracts dependency name/version pairs from "dependencies"' {
            $deps = Get-ManifestDependency -Path $fixture
            ($deps | Where-Object Name -eq 'lodash').Version | Should -Be '4.17.21'
        }

        It 'extracts dependency name/version pairs from "devDependencies"' {
            $deps = Get-ManifestDependency -Path $fixture
            ($deps | Where-Object Name -eq 'jest').Version | Should -Be '29.7.0'
        }

        It 'returns one object per dependency with Name and Version properties' {
            $deps = Get-ManifestDependency -Path $fixture
            $deps | ForEach-Object {
                $_.PSObject.Properties.Name | Should -Contain 'Name'
                $_.PSObject.Properties.Name | Should -Contain 'Version'
            }
        }
    }

    Context 'requirements.txt manifests' {
        BeforeAll {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "requirements-$([guid]::NewGuid()).txt"
            @(
                '# a comment should be ignored'
                ''
                'requests==2.31.0'
                'flask>=2.0.0'
                'certifi'
            ) | Set-Content -Path $tempFile
            $script:reqFixture = $tempFile
        }

        AfterAll {
            Remove-Item -Path $script:reqFixture -ErrorAction SilentlyContinue
        }

        It 'parses pinned versions (==)' {
            $deps = Get-ManifestDependency -Path $script:reqFixture
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
        }

        It 'parses minimum-bound versions (>=)' {
            $deps = Get-ManifestDependency -Path $script:reqFixture
            ($deps | Where-Object Name -eq 'flask').Version | Should -Be '2.0.0'
        }

        It 'handles unpinned packages with an "unspecified" version' {
            $deps = Get-ManifestDependency -Path $script:reqFixture
            ($deps | Where-Object Name -eq 'certifi').Version | Should -Be 'unspecified'
        }

        It 'ignores blank lines and comments' {
            $deps = Get-ManifestDependency -Path $script:reqFixture
            $deps.Count | Should -Be 3
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the manifest file does not exist' {
            { Get-ManifestDependency -Path './does-not-exist.json' } |
                Should -Throw '*not found*'
        }

        It 'throws a meaningful error for an unrecognized manifest file name' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "unsupported-$([guid]::NewGuid()).toml"
            Set-Content -Path $tempFile -Value 'name = "x"'
            try {
                { Get-ManifestDependency -Path $tempFile } |
                    Should -Throw '*Unsupported manifest*'
            }
            finally {
                Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            }
        }

        It 'throws a meaningful error when package.json is malformed' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "bad-$([guid]::NewGuid()).json"
            Set-Content -Path $tempFile -Value '{ this is not valid json'
            try {
                { Get-ManifestDependency -Path $tempFile } |
                    Should -Throw '*Failed to parse*'
            }
            finally {
                Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-PackageLicense' {
    Context 'looking up against a license database file' {
        BeforeAll {
            $dbFixture = Join-Path $PSScriptRoot '..' 'fixtures' 'license-database-fixture.json'
            @{
                lodash = 'MIT'
                'gpl-package' = 'GPL-3.0'
            } | ConvertTo-Json | Set-Content -Path $dbFixture
            $script:dbFixture = $dbFixture
        }

        AfterAll {
            Remove-Item -Path $script:dbFixture -ErrorAction SilentlyContinue
        }

        It 'returns the license for a known package' {
            Get-PackageLicense -Name 'lodash' -LicenseDatabasePath $script:dbFixture |
                Should -Be 'MIT'
        }

        It 'returns $null for a package missing from the database' {
            Get-PackageLicense -Name 'totally-unknown-package' -LicenseDatabasePath $script:dbFixture |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-LicenseStatus' {
    BeforeAll {
        $allowList = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $denyList = @('GPL-3.0', 'AGPL-3.0')
        $script:allowList = $allowList
        $script:denyList = $denyList
    }

    It 'marks a license on the allow-list as Approved' {
        Resolve-LicenseStatus -License 'MIT' -AllowList $script:allowList -DenyList $script:denyList |
            Should -Be 'Approved'
    }

    It 'marks a license on the deny-list as Denied' {
        Resolve-LicenseStatus -License 'GPL-3.0' -AllowList $script:allowList -DenyList $script:denyList |
            Should -Be 'Denied'
    }

    It 'marks a license on neither list as Unknown' {
        Resolve-LicenseStatus -License 'WTFPL' -AllowList $script:allowList -DenyList $script:denyList |
            Should -Be 'Unknown'
    }

    It 'marks a missing/null license as Unknown' {
        Resolve-LicenseStatus -License $null -AllowList $script:allowList -DenyList $script:denyList |
            Should -Be 'Unknown'
    }

    It 'prefers Denied over Approved when a license appears on both lists (fail-safe)' {
        Resolve-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') |
            Should -Be 'Denied'
    }
}

Describe 'New-LicenseComplianceReport' {
    BeforeAll {
        $script:manifestFixture = Join-Path $PSScriptRoot '..' 'fixtures' 'package-allowed.json'
        $script:policyFixture = Join-Path $PSScriptRoot '..' 'fixtures' 'policy-fixture.json'
        @{
            AllowList = @('MIT', 'Apache-2.0')
            DenyList  = @('GPL-3.0')
        } | ConvertTo-Json | Set-Content -Path $script:policyFixture
    }

    AfterAll {
        Remove-Item -Path $script:policyFixture -ErrorAction SilentlyContinue
    }

    It 'builds one report row per dependency using the mocked license lookup' {
        Mock -ModuleName LicenseChecker Get-PackageLicense {
            switch ($Name) {
                'lodash' { return 'MIT' }
                'chalk'  { return 'MIT' }
                'jest'   { return 'GPL-3.0' }
                default  { return $null }
            }
        }

        $report = New-LicenseComplianceReport -ManifestPath $script:manifestFixture -PolicyPath $script:policyFixture -LicenseDatabasePath 'unused.json'

        ($report.Dependencies | Where-Object Name -eq 'lodash').Status | Should -Be 'Approved'
        ($report.Dependencies | Where-Object Name -eq 'jest').Status | Should -Be 'Denied'
        Should -Invoke -ModuleName LicenseChecker Get-PackageLicense -Times 3 -Exactly
    }

    It 'summarizes approved/denied/unknown counts' {
        Mock -ModuleName LicenseChecker Get-PackageLicense {
            switch ($Name) {
                'lodash' { return 'MIT' }
                'chalk'  { return 'Apache-2.0' }
                'jest'   { return $null }
                default  { return $null }
            }
        }

        $report = New-LicenseComplianceReport -ManifestPath $script:manifestFixture -PolicyPath $script:policyFixture -LicenseDatabasePath 'unused.json'

        $report.Summary.Approved | Should -Be 2
        $report.Summary.Denied | Should -Be 0
        $report.Summary.Unknown | Should -Be 1
    }

    It 'throws a meaningful error when the policy file is missing' {
        Mock -ModuleName LicenseChecker Get-PackageLicense { 'MIT' }
        { New-LicenseComplianceReport -ManifestPath $script:manifestFixture -PolicyPath './no-such-policy.json' -LicenseDatabasePath 'unused.json' } |
            Should -Throw '*Policy file not found*'
    }
}
