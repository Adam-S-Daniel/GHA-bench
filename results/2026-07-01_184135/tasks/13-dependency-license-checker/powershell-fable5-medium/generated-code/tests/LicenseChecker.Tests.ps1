<#
.SYNOPSIS
    Pester tests for the dependency license checker.

.DESCRIPTION
    Built with red/green TDD. Each Describe block below corresponds to one
    TDD cycle (test written first, watched fail, then the minimum code was
    added to src/LicenseChecker.psm1 to make it pass, then refactored):

      Cycle 1: Get-DependencyList  - parse package.json
      (later cycles appended below as functionality grew)

    The license lookup is mocked two ways:
      * Pester `Mock` on Get-DependencyLicense for report-level tests
      * a JSON fixture "license database" file, which is also what the CI
        pipeline uses so runs are deterministic and offline.
#>

BeforeAll {
    # Import the module under test fresh for every run.
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $ModulePath -Force

    # Directory for throwaway fixture files created by individual tests.
    $script:FixtureDir = Join-Path ([IO.Path]::GetTempPath()) "lc-tests-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:FixtureDir | Out-Null
}

AfterAll {
    Remove-Item -Recurse -Force $script:FixtureDir -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
# TDD Cycle 1: parse a package.json manifest into (Name, Version) records
# --------------------------------------------------------------------------
Describe 'Get-DependencyList (package.json)' {
    BeforeAll {
        $script:PkgJsonPath = Join-Path $script:FixtureDir 'package.json'
        @'
{
  "name": "fixture-app",
  "dependencies": {
    "express": "4.18.2",
    "evil-lib": "^2.0.0"
  },
  "devDependencies": {
    "left-pad": "~1.3.0"
  }
}
'@ | Set-Content -Path $script:PkgJsonPath
    }

    It 'returns one record per dependency including devDependencies' {
        $deps = Get-DependencyList -ManifestPath $script:PkgJsonPath
        $deps.Count | Should -Be 3
        $deps.Name | Should -Contain 'express'
        $deps.Name | Should -Contain 'evil-lib'
        $deps.Name | Should -Contain 'left-pad'
    }

    It 'strips semver range prefixes (^, ~, >=) from versions' {
        $deps = Get-DependencyList -ManifestPath $script:PkgJsonPath
        ($deps | Where-Object Name -eq 'express').Version  | Should -Be '4.18.2'
        ($deps | Where-Object Name -eq 'evil-lib').Version | Should -Be '2.0.0'
        ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
    }

    It 'throws a meaningful error for a missing manifest file' {
        { Get-DependencyList -ManifestPath (Join-Path $script:FixtureDir 'nope.json') } |
            Should -Throw '*Manifest file not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        $bad = Join-Path $script:FixtureDir 'bad-package.json'
        '{ not json' | Set-Content -Path $bad
        { Get-DependencyList -ManifestPath $bad } |
            Should -Throw '*not valid JSON*'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 2: parse a requirements.txt manifest
# --------------------------------------------------------------------------
Describe 'Get-DependencyList (requirements.txt)' {
    BeforeAll {
        $script:ReqPath = Join-Path $script:FixtureDir 'requirements.txt'
        @'
# production deps
requests==2.31.0
flask==3.0.0

mystery-pkg==0.1.0
loose-pin>=1.2
'@ | Set-Content -Path $script:ReqPath
    }

    It 'parses pinned requirements and skips comments and blank lines' {
        $deps = Get-DependencyList -ManifestPath $script:ReqPath
        $deps.Count | Should -Be 4
        ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
        ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '3.0.0'
    }

    It 'captures the version from non-pinned specifiers too' {
        $deps = Get-DependencyList -ManifestPath $script:ReqPath
        ($deps | Where-Object Name -eq 'loose-pin').Version | Should -Be '1.2'
    }

    It 'throws for an unsupported manifest type' {
        $weird = Join-Path $script:FixtureDir 'Gemfile'
        'gem "rails"' | Set-Content -Path $weird
        { Get-DependencyList -ManifestPath $weird } |
            Should -Throw '*Unsupported manifest*'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 3: classify a license against allow/deny lists
# --------------------------------------------------------------------------
Describe 'Get-LicenseStatus' {
    BeforeAll {
        $script:Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $script:Deny  = @('GPL-3.0', 'SSPL-1.0')
    }

    It 'returns Approved for an allow-listed license' {
        Get-LicenseStatus -License 'MIT' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'Approved'
    }

    It 'returns Denied for a deny-listed license' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'Denied'
    }

    It 'returns Unknown for a license on neither list' {
        Get-LicenseStatus -License 'WTFPL' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'Unknown'
    }

    It 'gives the deny list precedence when a license is on both lists' {
        Get-LicenseStatus -License 'MIT' -AllowList $script:Allow -DenyList @('MIT') |
            Should -Be 'Denied'
    }

    It 'returns Unknown for an empty or missing license' {
        Get-LicenseStatus -License '' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'Unknown'
    }

    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit' -AllowList $script:Allow -DenyList $script:Deny |
            Should -Be 'Approved'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 4: mockable license lookup backed by a JSON "database" file
# --------------------------------------------------------------------------
Describe 'Get-DependencyLicense' {
    BeforeAll {
        $script:DbPath = Join-Path $script:FixtureDir 'mock-licenses.json'
        '{ "express": "MIT", "evil-lib": "GPL-3.0" }' | Set-Content -Path $script:DbPath
    }

    It 'returns the license recorded in the database for a known package' {
        Get-DependencyLicense -Name 'express' -LicenseDatabasePath $script:DbPath |
            Should -Be 'MIT'
    }

    It 'returns $null for a package not in the database' {
        Get-DependencyLicense -Name 'left-pad' -LicenseDatabasePath $script:DbPath |
            Should -BeNullOrEmpty
    }

    It 'throws a meaningful error when the database file is missing' {
        { Get-DependencyLicense -Name 'x' -LicenseDatabasePath (Join-Path $script:FixtureDir 'no-db.json') } |
            Should -Throw '*License database not found*'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 5: end-to-end compliance report (lookup mocked with Pester Mock)
# --------------------------------------------------------------------------
Describe 'New-ComplianceReport' {
    BeforeAll {
        $script:ConfigPath = Join-Path $script:FixtureDir 'license-config.json'
        @'
{ "allowList": ["MIT", "Apache-2.0"], "denyList": ["GPL-3.0"] }
'@ | Set-Content -Path $script:ConfigPath

        $script:PkgPath = Join-Path $script:FixtureDir 'report-package.json'
        @'
{ "dependencies": { "express": "4.18.2", "evil-lib": "2.0.0", "left-pad": "1.3.0" } }
'@ | Set-Content -Path $script:PkgPath
    }

    It 'classifies every dependency using the (mocked) license lookup' {
        # Mock the lookup so no real license service / db file is consulted.
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            @{ 'express' = 'MIT'; 'evil-lib' = 'GPL-3.0' }[$Name]
        }

        $report = New-ComplianceReport -ManifestPath $script:PkgPath -ConfigPath $script:ConfigPath
        $report.Entries.Count | Should -Be 3

        ($report.Entries | Where-Object Name -eq 'express').Status  | Should -Be 'Approved'
        ($report.Entries | Where-Object Name -eq 'evil-lib').Status | Should -Be 'Denied'
        # left-pad has no license in the mock -> reported as UNKNOWN/Unknown
        $lp = $report.Entries | Where-Object Name -eq 'left-pad'
        $lp.License | Should -Be 'UNKNOWN'
        $lp.Status  | Should -Be 'Unknown'
    }

    It 'produces accurate summary counts' {
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            @{ 'express' = 'MIT'; 'evil-lib' = 'GPL-3.0' }[$Name]
        }

        $report = New-ComplianceReport -ManifestPath $script:PkgPath -ConfigPath $script:ConfigPath
        $report.Summary.Approved | Should -Be 1
        $report.Summary.Denied   | Should -Be 1
        $report.Summary.Unknown  | Should -Be 1
        $report.Summary.Total    | Should -Be 3
    }

    It 'sorts entries by dependency name for deterministic output' {
        Mock -ModuleName LicenseChecker Get-DependencyLicense { 'MIT' }
        $report = New-ComplianceReport -ManifestPath $script:PkgPath -ConfigPath $script:ConfigPath
        $report.Entries.Name -join ',' | Should -Be 'evil-lib,express,left-pad'
    }

    It 'throws a meaningful error for a malformed config file' {
        $badCfg = Join-Path $script:FixtureDir 'bad-config.json'
        '{ oops' | Set-Content -Path $badCfg
        { New-ComplianceReport -ManifestPath $script:PkgPath -ConfigPath $badCfg } |
            Should -Throw '*not valid JSON*'
    }

    It 'formats report lines in the machine-readable RESULT|/SUMMARY| shape' {
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            @{ 'express' = 'MIT'; 'evil-lib' = 'GPL-3.0' }[$Name]
        }
        $report = New-ComplianceReport -ManifestPath $script:PkgPath -ConfigPath $script:ConfigPath
        $lines  = Format-ComplianceReport -Report $report

        $lines | Should -Contain 'RESULT|express|4.18.2|MIT|Approved'
        $lines | Should -Contain 'RESULT|evil-lib|2.0.0|GPL-3.0|Denied'
        $lines | Should -Contain 'RESULT|left-pad|1.3.0|UNKNOWN|Unknown'
        $lines | Should -Contain 'SUMMARY|Approved=1|Denied=1|Unknown=1|Total=3'
    }
}
