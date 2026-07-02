<#
.SYNOPSIS
    Pester unit tests for the DependencyLicenseChecker module.

.DESCRIPTION
    Built with red/green TDD. Each Describe block corresponds to one TDD cycle:
      Cycle 1: Get-Dependencies parses package.json
      (later cycles appended below as functionality grows)

    Unit tests generate their input files under TestDrive so they are fully
    isolated; the license lookup is mocked (both via a mock JSON "registry"
    database file and via Pester's Mock for module-internal calls).
#>

BeforeAll {
    # Import the module under test fresh for every run.
    $modulePath = Join-Path $PSScriptRoot '..' 'DependencyLicenseChecker.psm1'
    Import-Module $modulePath -Force
}

# --------------------------------------------------------------------------
# TDD Cycle 1: parse a package.json manifest into Name/Version objects
# --------------------------------------------------------------------------
Describe 'Get-Dependencies (package.json)' {
    BeforeAll {
        # Fixture: a small npm manifest with both runtime and dev dependencies.
        $script:manifest = Join-Path $TestDrive 'package.json'
        @'
{
  "name": "sample-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "left-pad": "1.3.0"
  },
  "devDependencies": {
    "mystery-lib": "~2.0.0"
  }
}
'@ | Set-Content -Path $script:manifest -Encoding utf8
        $script:deps = Get-Dependencies -ManifestPath $script:manifest
    }

    It 'returns one entry per dependency (including devDependencies)' {
        $deps | Should -HaveCount 3
    }

    It 'extracts dependency names' {
        $deps.Name | Should -Contain 'express'
        $deps.Name | Should -Contain 'left-pad'
        $deps.Name | Should -Contain 'mystery-lib'
    }

    It 'normalizes semver range prefixes (^, ~) away from versions' {
        ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
        ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
        ($deps | Where-Object Name -eq 'mystery-lib').Version | Should -Be '2.0.0'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 2: parse requirements.txt + graceful error handling
# --------------------------------------------------------------------------
Describe 'Get-Dependencies (requirements.txt)' {
    BeforeAll {
        # Fixture: pip requirements with comments, blank lines and mixed
        # version specifiers.
        $script:manifest = Join-Path $TestDrive 'requirements.txt'
        @'
# Web stack
requests==2.31.0
flask>=2.3.0

copyleft-lib==1.0.0   # inline comment
unknown-package==0.5.0
'@ | Set-Content -Path $script:manifest -Encoding utf8
        $script:deps = Get-Dependencies -ManifestPath $script:manifest
    }

    It 'skips comments and blank lines' {
        $deps | Should -HaveCount 4
    }

    It 'extracts names and pinned versions' {
        ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
        ($deps | Where-Object Name -eq 'copyleft-lib').Version | Should -Be '1.0.0'
    }

    It 'extracts the version from range specifiers like >=' {
        ($deps | Where-Object Name -eq 'flask').Version | Should -Be '2.3.0'
    }
}

Describe 'Get-Dependencies (error handling)' {
    It 'throws a meaningful error when the manifest does not exist' {
        { Get-Dependencies -ManifestPath (Join-Path $TestDrive 'nope.json') } |
            Should -Throw '*Manifest file not found*'
    }

    It 'throws a meaningful error for unsupported manifest formats' {
        $file = Join-Path $TestDrive 'Gemfile'
        'gem "rails"' | Set-Content -Path $file
        { Get-Dependencies -ManifestPath $file } |
            Should -Throw '*Unsupported manifest format*'
    }

    It 'throws a meaningful error for invalid JSON in package.json' {
        $file = Join-Path $TestDrive 'broken/package.json'
        New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null
        '{ not valid json' | Set-Content -Path $file
        { Get-Dependencies -ManifestPath $file } |
            Should -Throw '*Failed to parse*'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 3: mocked license lookup + allow/deny classification
# --------------------------------------------------------------------------
Describe 'Get-DependencyLicense (mock registry database)' {
    BeforeAll {
        # The license "registry" is mocked as a local JSON file mapping
        # package name -> SPDX license id (stands in for a real registry API).
        $script:db = Join-Path $TestDrive 'mock-license-db.json'
        @'
{
  "express": "MIT",
  "left-pad": "WTFPL"
}
'@ | Set-Content -Path $script:db -Encoding utf8
    }

    It 'returns the license for a known package' {
        Get-DependencyLicense -Name 'express' -LicenseDatabasePath $db | Should -Be 'MIT'
    }

    It 'returns $null for a package missing from the database' {
        Get-DependencyLicense -Name 'mystery-lib' -LicenseDatabasePath $db | Should -BeNullOrEmpty
    }

    It 'throws a meaningful error when the database file is missing' {
        { Get-DependencyLicense -Name 'express' -LicenseDatabasePath (Join-Path $TestDrive 'no-db.json') } |
            Should -Throw '*License database not found*'
    }
}

Describe 'Get-LicenseStatus' {
    BeforeAll {
        $script:allow = @('MIT', 'Apache-2.0')
        $script:deny  = @('GPL-3.0', 'WTFPL')
    }

    It 'classifies an allow-listed license as approved' {
        Get-LicenseStatus -License 'MIT' -Allow $allow -Deny $deny | Should -Be 'approved'
    }

    It 'classifies a deny-listed license as denied' {
        Get-LicenseStatus -License 'WTFPL' -Allow $allow -Deny $deny | Should -Be 'denied'
    }

    It 'classifies a license on neither list as unknown' {
        Get-LicenseStatus -License 'BSD-3-Clause' -Allow $allow -Deny $deny | Should -Be 'unknown'
    }

    It 'classifies a missing license as unknown' {
        Get-LicenseStatus -License $null -Allow $allow -Deny $deny | Should -Be 'unknown'
    }

    It 'treats the deny list as taking precedence over the allow list' {
        # A license accidentally present on both lists must be denied.
        Get-LicenseStatus -License 'MIT' -Allow $allow -Deny @('MIT') | Should -Be 'denied'
    }

    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit' -Allow $allow -Deny $deny | Should -Be 'approved'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 4: config loading, report generation (with a Pester Mock for the
# license lookup) and the end-to-end orchestrator
# --------------------------------------------------------------------------
Describe 'Get-LicenseConfig' {
    It 'loads allow and deny lists from a JSON config file' {
        $cfg = Join-Path $TestDrive 'config.json'
        '{ "allow": ["MIT"], "deny": ["GPL-3.0"] }' | Set-Content -Path $cfg
        $config = Get-LicenseConfig -ConfigPath $cfg
        $config.Allow | Should -Be @('MIT')
        $config.Deny | Should -Be @('GPL-3.0')
    }

    It 'defaults missing lists to empty arrays' {
        $cfg = Join-Path $TestDrive 'config-allow-only.json'
        '{ "allow": ["MIT"] }' | Set-Content -Path $cfg
        $config = Get-LicenseConfig -ConfigPath $cfg
        $config.Deny | Should -HaveCount 0
    }

    It 'throws a meaningful error when the config file is missing' {
        { Get-LicenseConfig -ConfigPath (Join-Path $TestDrive 'no-config.json') } |
            Should -Throw '*Config file not found*'
    }

    It 'throws a meaningful error for invalid JSON config' {
        $cfg = Join-Path $TestDrive 'bad-config.json'
        'not json at all {' | Set-Content -Path $cfg
        { Get-LicenseConfig -ConfigPath $cfg } |
            Should -Throw '*Failed to parse*'
    }
}

Describe 'New-ComplianceReport' {
    BeforeAll {
        $script:config = [pscustomobject]@{
            Allow = @('MIT', 'Apache-2.0')
            Deny  = @('WTFPL')
        }
        $script:dependencies = @(
            [pscustomobject]@{ Name = 'express';     Version = '4.18.2' }
            [pscustomobject]@{ Name = 'left-pad';    Version = '1.3.0' }
            [pscustomobject]@{ Name = 'mystery-lib'; Version = '2.0.0' }
        )
    }

    It 'classifies each dependency using the (mocked) license lookup' {
        # Pester Mock replaces the module-internal registry lookup entirely —
        # no database file is touched here.
        Mock -ModuleName DependencyLicenseChecker Get-DependencyLicense {
            switch ($Name) {
                'express'  { 'MIT' }
                'left-pad' { 'WTFPL' }
                default    { $null }
            }
        }

        $report = New-ComplianceReport -Dependencies $dependencies -Config $config -LicenseDatabasePath 'ignored-by-mock.json'

        $report | Should -HaveCount 3
        ($report | Where-Object Name -eq 'express').Status | Should -Be 'approved'
        ($report | Where-Object Name -eq 'left-pad').Status | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery-lib').Status | Should -Be 'unknown'

        # Every dependency triggered exactly one lookup.
        Should -Invoke Get-DependencyLicense -ModuleName DependencyLicenseChecker -Times 3 -Exactly
    }

    It 'reports UNKNOWN as the license text when the lookup finds nothing' {
        Mock -ModuleName DependencyLicenseChecker Get-DependencyLicense { $null }
        $report = New-ComplianceReport -Dependencies $dependencies -Config $config -LicenseDatabasePath 'ignored.json'
        $report.License | Should -Be @('UNKNOWN', 'UNKNOWN', 'UNKNOWN')
    }
}

Describe 'Invoke-LicenseCheck (end to end with repo fixtures)' {
    BeforeAll {
        $script:fixtures = Join-Path $PSScriptRoot '..' 'fixtures'
        $script:report = Invoke-LicenseCheck `
            -ManifestPath (Join-Path $fixtures 'package.json') `
            -ConfigPath (Join-Path $fixtures 'license-config.json') `
            -LicenseDatabasePath (Join-Path $fixtures 'mock-license-db.json')
    }

    It 'produces a full report from manifest + config + mock database' {
        $report | Should -HaveCount 3
        ($report | Where-Object Name -eq 'express').License | Should -Be 'MIT'
        ($report | Where-Object Name -eq 'express').Status | Should -Be 'approved'
        ($report | Where-Object Name -eq 'left-pad').Status | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery-lib').Status | Should -Be 'unknown'
    }

    It 'works for requirements.txt manifests too' {
        $pipReport = Invoke-LicenseCheck `
            -ManifestPath (Join-Path $fixtures 'requirements.txt') `
            -ConfigPath (Join-Path $fixtures 'license-config.json') `
            -LicenseDatabasePath (Join-Path $fixtures 'mock-license-db.json')

        $pipReport | Should -HaveCount 4
        ($pipReport | Where-Object Name -eq 'requests').Status | Should -Be 'approved'
        ($pipReport | Where-Object Name -eq 'copyleft-lib').Status | Should -Be 'denied'
        ($pipReport | Where-Object Name -eq 'unknown-package').Status | Should -Be 'unknown'
    }
}

# --------------------------------------------------------------------------
# TDD Cycle 5: CLI entry script (check-licenses.ps1) — stable, machine-
# readable output that the CI pipeline asserts on. The script is exercised
# in a child pwsh process so exit codes are observable.
# --------------------------------------------------------------------------
Describe 'check-licenses.ps1 CLI' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:cli = Join-Path $root 'check-licenses.ps1'

        function Invoke-Cli {
            # Run the CLI in a fresh pwsh so $LASTEXITCODE reflects the script.
            param([string[]]$ArgumentList)
            $output = & pwsh -NoProfile -File $script:cli @ArgumentList 2>&1
            [pscustomobject]@{ Output = $output -join "`n"; ExitCode = $LASTEXITCODE }
        }

        $script:run = Invoke-Cli @(
            '-ManifestPath', (Join-Path $root 'fixtures/package.json'),
            '-ConfigPath', (Join-Path $root 'fixtures/license-config.json'),
            '-LicenseDatabasePath', (Join-Path $root 'fixtures/mock-license-db.json'),
            '-OutputPath', (Join-Path $TestDrive 'report.json')
        )
    }

    It 'exits 0 on a successful run' {
        $run.ExitCode | Should -Be 0
    }

    It 'emits one RESULT line per dependency with exact pipe-delimited fields' {
        $run.Output | Should -Match ([regex]::Escape('RESULT|express|4.18.2|MIT|approved'))
        $run.Output | Should -Match ([regex]::Escape('RESULT|left-pad|1.3.0|WTFPL|denied'))
        $run.Output | Should -Match ([regex]::Escape('RESULT|mystery-lib|2.0.0|UNKNOWN|unknown'))
    }

    It 'emits an exact SUMMARY line with per-status counts' {
        $run.Output | Should -Match ([regex]::Escape('SUMMARY|approved=1|denied=1|unknown=1'))
    }

    It 'writes the JSON report to -OutputPath' {
        $json = Get-Content (Join-Path $TestDrive 'report.json') -Raw | ConvertFrom-Json
        $json | Should -HaveCount 3
        ($json | Where-Object Name -eq 'left-pad').Status | Should -Be 'denied'
    }

    It 'fails with exit code 1 and a meaningful message for a missing manifest' {
        $bad = Invoke-Cli @(
            '-ManifestPath', (Join-Path $TestDrive 'missing.json'),
            '-ConfigPath', (Join-Path $root 'fixtures/license-config.json'),
            '-LicenseDatabasePath', (Join-Path $root 'fixtures/mock-license-db.json')
        )
        $bad.ExitCode | Should -Be 1
        $bad.Output | Should -Match 'Manifest file not found'
    }

    It 'exits 2 when -FailOnDenied is set and a denied license is present' {
        $denied = Invoke-Cli @(
            '-ManifestPath', (Join-Path $root 'fixtures/package.json'),
            '-ConfigPath', (Join-Path $root 'fixtures/license-config.json'),
            '-LicenseDatabasePath', (Join-Path $root 'fixtures/mock-license-db.json'),
            '-FailOnDenied'
        )
        $denied.ExitCode | Should -Be 2
    }
}
