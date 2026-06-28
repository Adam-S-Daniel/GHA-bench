# LicenseChecker.Tests.ps1
#
# Pester test suite for the dependency license compliance checker.
#
# These tests are written using red/green TDD: each `Describe`/`It` block was
# authored to fail first, then the minimum code in src/LicenseChecker.psm1 was
# written to make it pass, then refactored. Run with `Invoke-Pester`.
#
# The "license lookup" is mocked throughout (via Pester `Mock` and via an
# in-memory license database) so the suite is fully deterministic and never
# touches the network.

BeforeAll {
    # Resolve paths relative to this test file so the suite runs from anywhere
    # (local dev, CI container, act, etc.).
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'src/LicenseChecker.psm1'
    $script:FixtureDir = Join-Path $RepoRoot 'fixtures'

    # Import the module under test fresh for every run.
    Import-Module $ModulePath -Force
}

Describe 'Get-Dependencies' {

    Context 'when given a package.json manifest' {
        BeforeAll {
            $script:PkgJson = Join-Path $TestDrive 'package.json'
            @'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "left-pad": "^1.3.0",
    "express": "4.18.2"
  },
  "devDependencies": {
    "jest": "~29.0.0"
  }
}
'@ | Set-Content -Path $PkgJson -Encoding utf8
        }

        It 'extracts every dependency name' {
            $deps = Get-Dependencies -ManifestPath $PkgJson
            $deps.Name | Should -Contain 'left-pad'
            $deps.Name | Should -Contain 'express'
            $deps.Name | Should -Contain 'jest'
        }

        It 'extracts the version for each dependency, stripping range prefixes' {
            $deps = Get-Dependencies -ManifestPath $PkgJson
            ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
            ($deps | Where-Object Name -eq 'express').Version  | Should -Be '4.18.2'
            ($deps | Where-Object Name -eq 'jest').Version     | Should -Be '29.0.0'
        }

        It 'includes both runtime and dev dependencies' {
            $deps = Get-Dependencies -ManifestPath $PkgJson
            $deps.Count | Should -Be 3
        }
    }

    Context 'when given a requirements.txt manifest' {
        BeforeAll {
            $script:ReqTxt = Join-Path $TestDrive 'requirements.txt'
            @'
# A sample pip requirements file
flask==2.3.2
requests>=2.28.0
numpy~=1.24.0

# comment line and a pip option below should be ignored
--hash=sha256:deadbeef
'@ | Set-Content -Path $ReqTxt -Encoding utf8
        }

        It 'extracts dependency names ignoring comments and options' {
            $deps = Get-Dependencies -ManifestPath $ReqTxt
            $deps.Name | Should -Contain 'flask'
            $deps.Name | Should -Contain 'requests'
            $deps.Name | Should -Contain 'numpy'
            $deps.Count | Should -Be 3
        }

        It 'extracts the pinned version, stripping operators' {
            $deps = Get-Dependencies -ManifestPath $ReqTxt
            ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '2.3.2'
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.28.0'
            ($deps | Where-Object Name -eq 'numpy').Version    | Should -Be '1.24.0'
        }
    }

    Context 'when the manifest is missing or unsupported' {
        It 'throws a meaningful error for a missing file' {
            { Get-Dependencies -ManifestPath (Join-Path $TestDrive 'nope.json') } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            $bad = Join-Path $TestDrive 'pom.xml'
            'irrelevant' | Set-Content -Path $bad
            { Get-Dependencies -ManifestPath $bad } |
                Should -Throw -ExpectedMessage '*Unsupported manifest type*'
        }
    }
}

Describe 'Get-LicenseStatus' {
    BeforeAll {
        $script:Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $script:Deny  = @('GPL-3.0', 'AGPL-3.0')
    }

    It 'returns "approved" for a license on the allow-list' {
        Get-LicenseStatus -License 'MIT' -AllowList $Allow -DenyList $Deny |
            Should -Be 'approved'
    }

    It 'returns "denied" for a license on the deny-list' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList $Allow -DenyList $Deny |
            Should -Be 'denied'
    }

    It 'returns "unknown" for a license on neither list' {
        Get-LicenseStatus -License 'WTFPL' -AllowList $Allow -DenyList $Deny |
            Should -Be 'unknown'
    }

    It 'returns "unknown" when the license is null or empty' {
        Get-LicenseStatus -License '' -AllowList $Allow -DenyList $Deny |
            Should -Be 'unknown'
    }

    It 'treats the deny-list as authoritative when a license is on both lists' {
        Get-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') |
            Should -Be 'denied'
    }

    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit' -AllowList $Allow -DenyList $Deny |
            Should -Be 'approved'
    }
}

Describe 'Resolve-DependencyLicense' {
    # This function stands in for a real registry/network lookup. In production
    # it would query npm/PyPI; here it reads from an in-memory database, which is
    # exactly the seam we mock for deterministic testing.
    BeforeAll {
        $script:Db = @{
            'left-pad' = 'WTFPL'
            'express'  = 'MIT'
            'jest'     = 'MIT'
        }
    }

    It 'returns the license recorded in the database' {
        Resolve-DependencyLicense -Name 'express' -Version '4.18.2' -LicenseDatabase $Db |
            Should -Be 'MIT'
    }

    It 'returns "UNKNOWN" when the package is not in the database' {
        Resolve-DependencyLicense -Name 'mystery' -Version '1.0.0' -LicenseDatabase $Db |
            Should -Be 'UNKNOWN'
    }

    It 'is case-insensitive on the package name' {
        Resolve-DependencyLicense -Name 'Express' -Version '4.18.2' -LicenseDatabase $Db |
            Should -Be 'MIT'
    }
}

Describe 'New-ComplianceReport' {
    BeforeAll {
        $script:Config = [pscustomobject]@{
            allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            deny  = @('GPL-3.0', 'AGPL-3.0', 'WTFPL')
        }
        $script:Deps = @(
            [pscustomobject]@{ Name = 'express';  Version = '4.18.2' }  # MIT  -> approved
            [pscustomobject]@{ Name = 'left-pad'; Version = '1.3.0' }   # WTFPL-> denied
            [pscustomobject]@{ Name = 'mystery';  Version = '9.9.9' }   # ?    -> unknown
        )
    }

    Context 'using Pester Mock to stub the license lookup' {
        BeforeEach {
            # Demonstrates the mock seam: New-ComplianceReport must call
            # Resolve-DependencyLicense, which we replace with a deterministic stub.
            Mock -ModuleName LicenseChecker Resolve-DependencyLicense {
                switch ($Name) {
                    'express'  { 'MIT' }
                    'left-pad' { 'WTFPL' }
                    default    { 'UNKNOWN' }
                }
            }
        }

        It 'produces one report item per dependency' {
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            $report.Items.Count | Should -Be 3
        }

        It 'classifies each dependency correctly' {
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            ($report.Items | Where-Object Name -eq 'express').Status  | Should -Be 'approved'
            ($report.Items | Where-Object Name -eq 'left-pad').Status | Should -Be 'denied'
            ($report.Items | Where-Object Name -eq 'mystery').Status  | Should -Be 'unknown'
        }

        It 'records the resolved license on each item' {
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            ($report.Items | Where-Object Name -eq 'express').License | Should -Be 'MIT'
        }

        It 'summarizes counts by status' {
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            $report.Summary.Total    | Should -Be 3
            $report.Summary.Approved | Should -Be 1
            $report.Summary.Denied   | Should -Be 1
            $report.Summary.Unknown  | Should -Be 1
        }

        It 'flags overall compliance as false when any dependency is denied' {
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            $report.Compliant | Should -BeFalse
        }

        It 'actually invokes the mocked lookup once per dependency' {
            New-ComplianceReport -Dependencies $Deps -Config $Config | Out-Null
            Should -Invoke -ModuleName LicenseChecker Resolve-DependencyLicense -Times 3 -Exactly
        }
    }

    Context 'when all dependencies are approved' {
        It 'flags overall compliance as true' {
            Mock -ModuleName LicenseChecker Resolve-DependencyLicense { 'MIT' }
            $report = New-ComplianceReport -Dependencies $Deps -Config $Config
            $report.Compliant | Should -BeTrue
            $report.Summary.Approved | Should -Be 3
        }
    }
}

Describe 'Format-ComplianceReport' {
    # Deterministic plain-text rendering. The CI workflow asserts on these exact
    # lines, so the format is part of the contract and is tested directly.
    BeforeAll {
        $script:Report = [pscustomobject]@{
            Items = @(
                [pscustomobject]@{ Name = 'express';  Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
                [pscustomobject]@{ Name = 'left-pad'; Version = '1.3.0';  License = 'WTFPL';   Status = 'denied' }
                [pscustomobject]@{ Name = 'mystery';  Version = '9.9.9';  License = 'UNKNOWN'; Status = 'unknown' }
            )
            Summary = [pscustomobject]@{ Total = 3; Approved = 1; Denied = 1; Unknown = 1 }
            Compliant = $false
        }
    }

    It 'renders one line per dependency with name, version, license and status' {
        $text = Format-ComplianceReport -Report $Report
        $text | Should -Match 'express@4\.18\.2 \[MIT\] -> APPROVED'
        $text | Should -Match 'left-pad@1\.3\.0 \[WTFPL\] -> DENIED'
        $text | Should -Match 'mystery@9\.9\.9 \[UNKNOWN\] -> UNKNOWN'
    }

    It 'renders a summary line with the counts' {
        $text = Format-ComplianceReport -Report $Report
        $text | Should -Match 'Total: 3 \| Approved: 1 \| Denied: 1 \| Unknown: 1'
    }

    It 'renders an overall FAIL verdict when not compliant' {
        $text = Format-ComplianceReport -Report $Report
        $text | Should -Match 'Compliance: FAIL'
    }

    It 'renders an overall PASS verdict when compliant' {
        $compliant = [pscustomobject]@{
            Items = @([pscustomobject]@{ Name = 'express'; Version = '4.18.2'; License = 'MIT'; Status = 'approved' })
            Summary = [pscustomobject]@{ Total = 1; Approved = 1; Denied = 0; Unknown = 0 }
            Compliant = $true
        }
        Format-ComplianceReport -Report $compliant | Should -Match 'Compliance: PASS'
    }
}
