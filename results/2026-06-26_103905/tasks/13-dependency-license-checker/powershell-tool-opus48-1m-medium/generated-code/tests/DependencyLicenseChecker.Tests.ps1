#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Unit tests for the Dependency License Checker.
# Written red/green TDD style: each Describe block was added test-first,
# then the corresponding function in the module was implemented to make it pass.

BeforeAll {
    # Resolve and import the module under test.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'DependencyLicenseChecker.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-DependencyList (manifest parsing)' {

    Context 'package.json' {
        BeforeAll {
            $script:pkgJson = Join-Path $TestDrive 'package.json'
            @'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "left-pad": "1.3.0"
  },
  "devDependencies": {
    "jest": "~29.5.0"
  }
}
'@ | Set-Content -Path $script:pkgJson -Encoding utf8
        }

        It 'extracts dependency names and normalized versions' {
            $deps = Get-DependencyList -ManifestPath $script:pkgJson
            $deps | Should -HaveCount 3
            ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
            ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
            ($deps | Where-Object Name -eq 'jest').Version | Should -Be '29.5.0'
        }

        It 'tags devDependencies appropriately' {
            $deps = Get-DependencyList -ManifestPath $script:pkgJson
            ($deps | Where-Object Name -eq 'jest').Scope | Should -Be 'dev'
            ($deps | Where-Object Name -eq 'express').Scope | Should -Be 'prod'
        }
    }

    Context 'requirements.txt' {
        BeforeAll {
            $script:reqTxt = Join-Path $TestDrive 'requirements.txt'
            @'
# Production dependencies
requests==2.31.0
flask>=2.3.0
numpy~=1.24.0

PyYAML==6.0
'@ | Set-Content -Path $script:reqTxt -Encoding utf8
        }

        It 'extracts names and versions, skipping comments and blanks' {
            $deps = Get-DependencyList -ManifestPath $script:reqTxt
            $deps | Should -HaveCount 4
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($deps | Where-Object Name -eq 'flask').Version | Should -Be '2.3.0'
            ($deps | Where-Object Name -eq 'PyYAML').Version | Should -Be '6.0'
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the manifest does not exist' {
            { Get-DependencyList -ManifestPath (Join-Path $TestDrive 'nope.json') } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error for unsupported manifest types' {
            $bad = Join-Path $TestDrive 'pom.xml'
            'x' | Set-Content -Path $bad
            { Get-DependencyList -ManifestPath $bad } |
                Should -Throw -ExpectedMessage '*Unsupported*'
        }

        It 'throws a meaningful error for malformed package.json' {
            $bad = Join-Path $TestDrive 'package.json'
            '{ this is not json' | Set-Content -Path $bad
            { Get-DependencyList -ManifestPath $bad } |
                Should -Throw -ExpectedMessage '*Failed to parse*'
        }
    }
}

Describe 'Get-DependencyLicense (mockable lookup)' {
    BeforeAll {
        $script:dbPath = Join-Path $TestDrive 'license-db.json'
        @'
{
  "express": "MIT",
  "left-pad": "WTFPL",
  "requests": "Apache-2.0"
}
'@ | Set-Content -Path $script:dbPath -Encoding utf8
    }

    It 'returns the license recorded in the database' {
        Get-DependencyLicense -Name 'express' -Version '4.18.2' -DatabasePath $script:dbPath |
            Should -Be 'MIT'
    }

    It 'returns UNKNOWN when the package is not in the database' {
        Get-DependencyLicense -Name 'ghost-pkg' -Version '9.9.9' -DatabasePath $script:dbPath |
            Should -Be 'UNKNOWN'
    }

    It 'can be mocked to simulate an external license service' {
        Mock -ModuleName DependencyLicenseChecker Get-LicenseFromDatabase { 'GPL-3.0' }
        Get-DependencyLicense -Name 'anything' -Version '1.0.0' -DatabasePath $script:dbPath |
            Should -Be 'GPL-3.0'
    }
}

Describe 'Test-LicenseStatus (allow/deny evaluation)' {
    It 'returns Approved for a license on the allow-list' {
        Test-LicenseStatus -License 'MIT' -AllowList @('MIT','Apache-2.0') -DenyList @('GPL-3.0') |
            Should -Be 'Approved'
    }

    It 'returns Denied for a license on the deny-list' {
        Test-LicenseStatus -License 'GPL-3.0' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'Denied'
    }

    It 'returns Unknown for a license on neither list' {
        Test-LicenseStatus -License 'WTFPL' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'Unknown'
    }

    It 'returns Unknown when the license itself is UNKNOWN' {
        Test-LicenseStatus -License 'UNKNOWN' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'Unknown'
    }

    It 'deny-list takes precedence over allow-list' {
        Test-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') |
            Should -Be 'Denied'
    }

    It 'matches licenses case-insensitively' {
        Test-LicenseStatus -License 'mit' -AllowList @('MIT') -DenyList @() |
            Should -Be 'Approved'
    }
}

Describe 'New-ComplianceReport (end-to-end orchestration)' {
    BeforeAll {
        $script:manifest = Join-Path $TestDrive 'package.json'
        @'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2",
    "evil-lib": "2.0.0",
    "mystery-lib": "0.1.0"
  }
}
'@ | Set-Content -Path $script:manifest -Encoding utf8

        $script:config = Join-Path $TestDrive 'config.json'
        @'
{
  "allowList": ["MIT", "Apache-2.0", "BSD-3-Clause"],
  "denyList": ["GPL-3.0", "AGPL-3.0"]
}
'@ | Set-Content -Path $script:config -Encoding utf8

        $script:db = Join-Path $TestDrive 'license-db.json'
        @'
{
  "express": "MIT",
  "evil-lib": "GPL-3.0"
}
'@ | Set-Content -Path $script:db -Encoding utf8
    }

    It 'produces a report row per dependency with the correct status' {
        $report = New-ComplianceReport -ManifestPath $script:manifest -ConfigPath $script:config -DatabasePath $script:db
        $report.Results | Should -HaveCount 3
        ($report.Results | Where-Object Name -eq 'express').Status | Should -Be 'Approved'
        ($report.Results | Where-Object Name -eq 'evil-lib').Status | Should -Be 'Denied'
        ($report.Results | Where-Object Name -eq 'mystery-lib').Status | Should -Be 'Unknown'
    }

    It 'summarizes counts by status' {
        $report = New-ComplianceReport -ManifestPath $script:manifest -ConfigPath $script:config -DatabasePath $script:db
        $report.Summary.Approved | Should -Be 1
        $report.Summary.Denied   | Should -Be 1
        $report.Summary.Unknown  | Should -Be 1
        $report.Summary.Total    | Should -Be 3
    }

    It 'reports overall compliance as failed when any dependency is denied' {
        $report = New-ComplianceReport -ManifestPath $script:manifest -ConfigPath $script:config -DatabasePath $script:db
        $report.Compliant | Should -BeFalse
    }

    It 'reports overall compliance as passed when nothing is denied' {
        $db2 = Join-Path $TestDrive 'license-db2.json'
        '{ "express": "MIT", "evil-lib": "MIT", "mystery-lib": "MIT" }' | Set-Content -Path $db2 -Encoding utf8
        $report = New-ComplianceReport -ManifestPath $script:manifest -ConfigPath $script:config -DatabasePath $db2
        $report.Compliant | Should -BeTrue
    }
}
