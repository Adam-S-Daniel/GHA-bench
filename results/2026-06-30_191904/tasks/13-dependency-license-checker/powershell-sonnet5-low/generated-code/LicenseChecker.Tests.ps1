# Pester tests for the dependency license checker.
# TDD: each Describe block below was written before its corresponding
# implementation in LicenseChecker.psm1.

BeforeAll {
    Import-Module "$PSScriptRoot/LicenseChecker.psm1" -Force
}

Describe 'Get-ManifestDependencies' {

    Context 'package.json manifests' {
        BeforeAll {
            $fixture = "$PSScriptRoot/fixtures/package.json"
        }

        It 'parses dependency names and versions from package.json' {
            $deps = Get-ManifestDependencies -Path $fixture
            $deps.Count | Should -Be 4
            ($deps | Where-Object Name -eq 'left-pad').Version | Should -Be '1.3.0'
        }

        It 'includes devDependencies as well as dependencies' {
            $deps = Get-ManifestDependencies -Path $fixture
            ($deps | Where-Object Name -eq 'eslint').Version | Should -Be '8.0.0'
        }
    }

    Context 'requirements.txt manifests' {
        BeforeAll {
            $fixture = "$PSScriptRoot/fixtures/requirements.txt"
        }

        It 'parses dependency names and pinned versions from requirements.txt' {
            $deps = Get-ManifestDependencies -Path $fixture
            $deps.Count | Should -Be 3
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
        }

        It 'ignores comments and blank lines' {
            $deps = Get-ManifestDependencies -Path $fixture
            ($deps | Where-Object Name -eq 'this-is-a-comment') | Should -BeNullOrEmpty
        }
    }

    Context 'missing or unsupported manifests' {
        It 'throws a meaningful error when the file does not exist' {
            { Get-ManifestDependencies -Path "$PSScriptRoot/fixtures/does-not-exist.json" } |
                Should -Throw '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            { Get-ManifestDependencies -Path "$PSScriptRoot/fixtures/unsupported.toml" } |
                Should -Throw '*Unsupported manifest*'
        }
    }
}

Describe 'Resolve-DependencyLicense' {
    It 'returns the license reported by the lookup function' {
        $lookup = { param($Name, $Version) 'MIT' }
        Resolve-DependencyLicense -Name 'left-pad' -Version '1.3.0' -LookupFunction $lookup |
            Should -Be 'MIT'
    }

    It 'returns Unknown when the lookup function throws' {
        $lookup = { param($Name, $Version) throw 'lookup failed' }
        Resolve-DependencyLicense -Name 'ghost-pkg' -Version '0.0.1' -LookupFunction $lookup |
            Should -Be 'Unknown'
    }

    It 'returns Unknown when the lookup function returns nothing' {
        $lookup = { param($Name, $Version) $null }
        Resolve-DependencyLicense -Name 'mystery-pkg' -Version '1.0.0' -LookupFunction $lookup |
            Should -Be 'Unknown'
    }
}

Describe 'Get-LicenseStatus' {
    BeforeAll {
        $policy = @{
            Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
            Deny  = @('GPL-3.0', 'AGPL-3.0')
        }
    }

    It 'classifies an allow-listed license as Approved' {
        Get-LicenseStatus -License 'MIT' -Policy $policy | Should -Be 'Approved'
    }

    It 'classifies a deny-listed license as Denied' {
        Get-LicenseStatus -License 'GPL-3.0' -Policy $policy | Should -Be 'Denied'
    }

    It 'classifies a license on neither list as Unknown' {
        Get-LicenseStatus -License 'MPL-2.0' -Policy $policy | Should -Be 'Unknown'
    }

    It 'classifies a missing license value as Unknown' {
        Get-LicenseStatus -License 'Unknown' -Policy $policy | Should -Be 'Unknown'
    }
}

Describe 'New-ComplianceReport' {
    BeforeAll {
        $policy = @{
            Allow = @('MIT')
            Deny  = @('GPL-3.0')
        }
        $mockLookup = {
            param($Name, $Version)
            switch ($Name) {
                'left-pad'  { 'MIT' }
                'gpl-thing' { 'GPL-3.0' }
                default     { $null }
            }
        }
    }

    It 'builds a report row per dependency with name, version, license and status' {
        $deps = @(
            [pscustomobject]@{ Name = 'left-pad'; Version = '1.3.0' },
            [pscustomobject]@{ Name = 'gpl-thing'; Version = '2.0.0' },
            [pscustomobject]@{ Name = 'mystery'; Version = '3.0.0' }
        )
        $report = New-ComplianceReport -Dependencies $deps -Policy $policy -LookupFunction $mockLookup

        $report.Count | Should -Be 3
        ($report | Where-Object Name -eq 'left-pad').Status  | Should -Be 'Approved'
        ($report | Where-Object Name -eq 'gpl-thing').Status | Should -Be 'Denied'
        ($report | Where-Object Name -eq 'mystery').Status   | Should -Be 'Unknown'
    }

    It 'reports overall HasViolations as true when any dependency is Denied' {
        $deps = @([pscustomobject]@{ Name = 'gpl-thing'; Version = '2.0.0' })
        $report = New-ComplianceReport -Dependencies $deps -Policy $policy -LookupFunction $mockLookup
        (Test-ComplianceViolations -Report $report) | Should -Be $true
    }

    It 'reports overall HasViolations as false when nothing is Denied' {
        $deps = @([pscustomobject]@{ Name = 'left-pad'; Version = '1.3.0' })
        $report = New-ComplianceReport -Dependencies $deps -Policy $policy -LookupFunction $mockLookup
        (Test-ComplianceViolations -Report $report) | Should -Be $false
    }
}

Describe 'Get-LicensePolicy' {
    It 'loads an Allow and Deny list from a JSON policy file' {
        $policy = Get-LicensePolicy -Path "$PSScriptRoot/fixtures/policy.json"
        $policy.Allow | Should -Contain 'MIT'
        $policy.Deny  | Should -Contain 'GPL-3.0'
    }
}
