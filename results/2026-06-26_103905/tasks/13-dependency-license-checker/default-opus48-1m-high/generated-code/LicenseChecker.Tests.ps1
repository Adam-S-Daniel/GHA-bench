#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester unit tests for the Dependency License Checker.

    These tests follow red/green TDD: each describe block was written as a
    failing test first, then the minimum implementation was added to
    LicenseChecker.psm1 to make it pass.

    The license lookup (Get-DependencyLicense) is the only piece that would,
    in a real system, reach out to an external registry. We MOCK it here so
    the tests are fully deterministic and offline.
#>

BeforeAll {
    # Import the module under test. $PSScriptRoot is the directory of this test file.
    $ModulePath = Join-Path $PSScriptRoot 'LicenseChecker.psm1'
    Import-Module $ModulePath -Force

    # Helper to create a throwaway fixture file (with a real manifest name) in
    # a unique temp directory, and return its path.
    function New-TempFile {
        param([string]$Content, [string]$FileName = 'fixture.tmp')
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $path = Join-Path $dir $FileName
        Set-Content -Path $path -Value $Content -Encoding utf8
        return $path
    }
}

Describe 'Get-Dependencies' {

    Context 'package.json manifests' {
        It 'extracts name and version from the dependencies object' {
            $json = @'
{
  "name": "demo",
  "dependencies": {
    "express": "4.18.2",
    "lodash": "^4.17.21"
  }
}
'@
            $path = New-TempFile -Content $json -FileName 'package.json'
            $deps = Get-Dependencies -ManifestPath $path

            $deps | Should -HaveCount 2
            ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
            # Semver range prefixes like ^ and ~ must be stripped.
            ($deps | Where-Object Name -eq 'lodash').Version  | Should -Be '4.17.21'
        }

        It 'also includes devDependencies' {
            $json = '{ "dependencies": { "a": "1.0.0" }, "devDependencies": { "b": "2.0.0" } }'
            $path = New-TempFile -Content $json -FileName 'package.json'
            $deps = Get-Dependencies -ManifestPath $path
            $deps | Should -HaveCount 2
            ($deps | Where-Object Name -eq 'b').Version | Should -Be '2.0.0'
        }

        It 'returns an empty result when there are no dependencies' {
            $path = New-TempFile -Content '{ "name": "empty" }' -FileName 'package.json'
            $deps = @(Get-Dependencies -ManifestPath $path)
            $deps | Should -HaveCount 0
        }

        It 'throws a meaningful error for malformed JSON' {
            $path = New-TempFile -Content '{ not valid json' -FileName 'package.json'
            { Get-Dependencies -ManifestPath $path } | Should -Throw '*Failed to parse*'
        }
    }

    Context 'requirements.txt manifests' {
        It 'parses pinned and ranged requirements, skipping comments and blanks' {
            $req = @'
# this is a comment
requests==2.31.0
flask>=2.0.0

PyYAML==6.0   # inline comment
some-pkg; python_version >= "3.8"
'@
            $path = New-TempFile -Content $req -FileName 'requirements.txt'
            $deps = Get-Dependencies -ManifestPath $path

            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '2.0.0'
            ($deps | Where-Object Name -eq 'PyYAML').Version   | Should -Be '6.0'
            # Environment markers are stripped; package with no version -> ''.
            ($deps | Where-Object Name -eq 'some-pkg').Version | Should -Be ''
            $deps | Should -HaveCount 4
        }
    }

    Context 'error handling' {
        It 'throws when the file does not exist' {
            { Get-Dependencies -ManifestPath '/no/such/file.json' } | Should -Throw '*not found*'
        }

        It 'throws for an unsupported manifest type' {
            $path = New-TempFile -Content 'whatever' -FileName 'Gemfile.lock'
            { Get-Dependencies -ManifestPath $path } | Should -Throw '*Unsupported manifest type*'
        }
    }
}

Describe 'Get-LicenseStatus' {
    It "returns 'denied' when the license is on the deny-list (deny wins over allow)" {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList @('MIT', 'GPL-3.0') -DenyList @('GPL-3.0') |
            Should -Be 'denied'
    }
    It "returns 'approved' when the license is only on the allow-list" {
        Get-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'approved'
    }
    It "returns 'unknown' when the license is on neither list" {
        Get-LicenseStatus -License 'WTFPL' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'unknown'
    }
    It "returns 'unknown' when the license is null or empty" {
        Get-LicenseStatus -License $null -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'unknown'
    }
    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit' -AllowList @('MIT') -DenyList @() |
            Should -Be 'approved'
    }
}

Describe 'Get-ComplianceConfig' {
    It 'loads allow and deny lists from a JSON config file' {
        $cfg = '{ "allow": ["MIT", "Apache-2.0"], "deny": ["GPL-3.0"] }'
        $path = New-TempFile -Content $cfg -FileName 'license-config.json'
        $config = Get-ComplianceConfig -ConfigPath $path
        $config.Allow | Should -Be @('MIT', 'Apache-2.0')
        $config.Deny  | Should -Be @('GPL-3.0')
    }

    It 'defaults missing lists to empty arrays' {
        $path = New-TempFile -Content '{ "allow": ["MIT"] }' -FileName 'license-config.json'
        $config = Get-ComplianceConfig -ConfigPath $path
        $config.Deny | Should -HaveCount 0
    }

    It 'throws a meaningful error when the config file is missing' {
        { Get-ComplianceConfig -ConfigPath '/no/such/config.json' } | Should -Throw '*not found*'
    }
}

Describe 'Get-DependencyLicense' {
    # The default implementation reads from a local license database file.
    # This is the production code path; the MOCK is exercised in New-ComplianceReport.
    It 'looks up a license by "name@version" then falls back to "name"' {
        $db = '{ "express@4.18.2": "MIT", "lodash": "MIT" }'
        $path = New-TempFile -Content $db -FileName 'license-db.json'
        $database = Get-LicenseDatabase -DatabasePath $path

        Get-DependencyLicense -Name 'express' -Version '4.18.2' -Database $database | Should -Be 'MIT'
        # Falls back to the name-only key when no exact version match exists.
        Get-DependencyLicense -Name 'lodash' -Version '9.9.9' -Database $database | Should -Be 'MIT'
        # Unknown package returns $null.
        Get-DependencyLicense -Name 'ghost' -Version '1.0.0' -Database $database | Should -BeNullOrEmpty
    }
}

Describe 'New-ComplianceReport' {
    # Here we MOCK the license lookup so the test never depends on a real
    # registry or database file — it is fully deterministic.
    BeforeEach {
        $script:manifest = New-TempFile -Content @'
{
  "dependencies": {
    "express": "4.18.2",
    "evil-pkg": "1.0.0",
    "mystery": "2.0.0"
  }
}
'@ -FileName 'package.json'
        $script:config = New-TempFile -Content '{ "allow": ["MIT"], "deny": ["GPL-3.0"] }' -FileName 'license-config.json'
    }

    It 'produces a row per dependency with the correct status, using the mocked lookup' {
        # Mock the seam: return a known license per package name.
        Mock -ModuleName LicenseChecker Get-DependencyLicense {
            switch ($Name) {
                'express'  { 'MIT' }
                'evil-pkg' { 'GPL-3.0' }
                default    { $null }   # 'mystery' -> unknown
            }
        }

        $report = New-ComplianceReport -ManifestPath $script:manifest -ConfigPath $script:config

        $report | Should -HaveCount 3
        ($report | Where-Object Name -eq 'express').Status  | Should -Be 'approved'
        ($report | Where-Object Name -eq 'evil-pkg').Status | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery').Status  | Should -Be 'unknown'
        ($report | Where-Object Name -eq 'mystery').License | Should -Be 'unknown'

        # Verify the mock was actually used (one call per dependency).
        Should -Invoke -ModuleName LicenseChecker Get-DependencyLicense -Times 3
    }
}

Describe 'Format-ComplianceReport' {
    It 'renders a table and an accurate summary line' {
        $report = @(
            [pscustomobject]@{ Name = 'express';  Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'evil-pkg'; Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied' }
            [pscustomobject]@{ Name = 'mystery';  Version = '2.0.0';  License = 'unknown'; Status = 'unknown' }
        )
        $text = Format-ComplianceReport -Report $report

        $text | Should -Match 'express\s+4\.18\.2\s+MIT\s+approved'
        $text | Should -Match 'evil-pkg\s+1\.0\.0\s+GPL-3\.0\s+denied'
        $text | Should -Match 'Summary: 1 approved, 1 denied, 1 unknown'
    }
}
