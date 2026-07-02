<#
    Pester unit tests for the DependencyLicenseChecker module.
    Written test-first (red/green TDD): each Describe block below was authored
    before the corresponding implementation existed in the module.
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot 'DependencyLicenseChecker.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-Dependencies (package.json)' {
    BeforeAll {
        $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $TempDir | Out-Null
        $ManifestPath = Join-Path $TempDir 'package.json'
        @'
{
  "name": "sample-app",
  "dependencies": {
    "left-pad": "^1.3.0",
    "gpl-lib": "2.0.0"
  },
  "devDependencies": {
    "mystery-pkg": "~1.0.0"
  }
}
'@ | Set-Content -LiteralPath $ManifestPath
    }

    AfterAll {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'extracts dependency names and clean versions from dependencies and devDependencies' {
        $deps = Get-Dependencies -ManifestPath $ManifestPath

        $deps.Count | Should -Be 3

        ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
        ($deps | Where-Object Name -eq 'gpl-lib').Version | Should -Be '2.0.0'
        ($deps | Where-Object Name -eq 'mystery-pkg').Version | Should -Be '1.0.0'
    }

    It 'throws a meaningful error when the manifest file does not exist' {
        { Get-Dependencies -ManifestPath (Join-Path $TempDir 'does-not-exist.json') } |
            Should -Throw '*not found*'
    }
}

Describe 'Get-Dependencies (requirements.txt)' {
    BeforeAll {
        $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $TempDir | Out-Null
        $ManifestPath = Join-Path $TempDir 'requirements.txt'
        @'
# a comment line should be ignored
requests==2.31.0
copyleft-pkg==1.0.0  # inline comment
obscure-pkg==0.1.0

-r other-requirements.txt
'@ | Set-Content -LiteralPath $ManifestPath
    }

    AfterAll {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'extracts dependency names and versions, ignoring comments and blank lines' {
        $deps = Get-Dependencies -ManifestPath $ManifestPath

        $deps.Count | Should -Be 3
        ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
        ($deps | Where-Object Name -eq 'copyleft-pkg').Version | Should -Be '1.0.0'
        ($deps | Where-Object Name -eq 'obscure-pkg').Version | Should -Be '0.1.0'
    }
}

Describe 'Get-Dependencies (unsupported manifest)' {
    BeforeAll {
        $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $TempDir | Out-Null
        $ManifestPath = Join-Path $TempDir 'Gemfile'
        'gem "rails"' | Set-Content -LiteralPath $ManifestPath
    }

    AfterAll {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'throws a meaningful error for an unsupported manifest type' {
        { Get-Dependencies -ManifestPath $ManifestPath } | Should -Throw '*Unsupported manifest format*'
    }
}

Describe 'Get-PackageLicense (mocked lookup)' {
    BeforeAll {
        # This hashtable stands in for a real registry/API call (npm, PyPI, etc.)
        # so tests never touch the network.
        $Lookup = @{
            'left-pad'     = 'MIT'
            'gpl-lib'      = 'GPL-3.0'
            'pinned-pkg@2.0.0' = 'Apache-2.0'
        }
    }

    It 'returns the license for a known package looked up by name' {
        Get-PackageLicense -Name 'left-pad' -Version '1.3.0' -LicenseLookup $Lookup | Should -Be 'MIT'
    }

    It 'prefers a version-specific match over a name-only match' {
        Get-PackageLicense -Name 'pinned-pkg' -Version '2.0.0' -LicenseLookup $Lookup | Should -Be 'Apache-2.0'
    }

    It 'returns UNKNOWN for a package absent from the lookup table' {
        Get-PackageLicense -Name 'mystery-pkg' -Version '1.0.0' -LicenseLookup $Lookup | Should -Be 'UNKNOWN'
    }
}

Describe 'Get-LicenseStatus' {
    BeforeAll {
        $AllowList = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $DenyList = @('GPL-3.0', 'AGPL-3.0')
    }

    It 'classifies a license on the allow-list as Approved' {
        Get-LicenseStatus -License 'MIT' -AllowList $AllowList -DenyList $DenyList | Should -Be 'Approved'
    }

    It 'classifies a license on the deny-list as Denied' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList $AllowList -DenyList $DenyList | Should -Be 'Denied'
    }

    It 'classifies a license on neither list as Unknown' {
        Get-LicenseStatus -License 'WTFPL' -AllowList $AllowList -DenyList $DenyList | Should -Be 'Unknown'
    }

    It 'classifies the UNKNOWN sentinel license as Unknown' {
        Get-LicenseStatus -License 'UNKNOWN' -AllowList $AllowList -DenyList $DenyList | Should -Be 'Unknown'
    }

    It 'treats deny-list as taking precedence when a license appears on both lists' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList @('GPL-3.0') -DenyList @('GPL-3.0') | Should -Be 'Denied'
    }
}

Describe 'New-ComplianceReport (integration)' {
    BeforeAll {
        $RepoRoot = $PSScriptRoot
        $ConfigPath = Join-Path $RepoRoot 'config/license-policy.json'
        $LookupPath = Join-Path $RepoRoot 'config/license-lookup-mock.json'
        $NpmManifest = Join-Path $RepoRoot 'fixtures/npm/package.json'
        $PythonManifest = Join-Path $RepoRoot 'fixtures/python/requirements.txt'
    }

    It 'produces Approved/Denied/Unknown statuses for an npm package.json' {
        $report = New-ComplianceReport -ManifestPath $NpmManifest -ConfigPath $ConfigPath -LicenseLookupPath $LookupPath

        $report.Count | Should -Be 3
        ($report | Where-Object Name -eq 'left-pad').Status | Should -Be 'Approved'
        ($report | Where-Object Name -eq 'gpl-lib').Status | Should -Be 'Denied'
        ($report | Where-Object Name -eq 'mystery-pkg').Status | Should -Be 'Unknown'
    }

    It 'produces Approved/Denied/Unknown statuses for a Python requirements.txt' {
        $report = New-ComplianceReport -ManifestPath $PythonManifest -ConfigPath $ConfigPath -LicenseLookupPath $LookupPath

        $report.Count | Should -Be 3
        ($report | Where-Object Name -eq 'requests').Status | Should -Be 'Approved'
        ($report | Where-Object Name -eq 'copyleft-pkg').Status | Should -Be 'Denied'
        ($report | Where-Object Name -eq 'obscure-pkg').Status | Should -Be 'Unknown'
    }

    It 'throws a meaningful error when the policy config is missing' {
        { New-ComplianceReport -ManifestPath $NpmManifest -ConfigPath (Join-Path $RepoRoot 'config/does-not-exist.json') -LicenseLookupPath $LookupPath } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the license lookup data is missing' {
        { New-ComplianceReport -ManifestPath $NpmManifest -ConfigPath $ConfigPath -LicenseLookupPath (Join-Path $RepoRoot 'config/does-not-exist.json') } |
            Should -Throw '*not found*'
    }
}
