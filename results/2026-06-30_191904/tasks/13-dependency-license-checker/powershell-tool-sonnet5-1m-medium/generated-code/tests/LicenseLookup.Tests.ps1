# Red/Green TDD - Step 2: license lookup + compliance classification.

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-PackageLicense' {
    BeforeEach {
        Clear-MockPackageLicense
    }

    It 'returns the license string reported by the lookup for a known package' {
        # Mock the underlying lookup so tests never hit the network.
        Set-MockPackageLicense -Name 'lodash' -Version '4.17.21' -License 'MIT'
        $license = Get-PackageLicense -Name 'lodash' -Version '4.17.21'
        $license | Should -Be 'MIT'
    }

    It 'returns "UNKNOWN" when the lookup has no data for the package' {
        $license = Get-PackageLicense -Name 'totally-unregistered-pkg' -Version '0.0.1'
        $license | Should -Be 'UNKNOWN'
    }
}

Describe 'Test-LicenseCompliance' {
    BeforeAll {
        $allowList = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $denyList  = @('GPL-3.0', 'AGPL-3.0')
    }

    It 'marks a license on the allow-list as Approved' {
        Test-LicenseCompliance -License 'MIT' -AllowList $allowList -DenyList $denyList | Should -Be 'Approved'
    }

    It 'marks a license on the deny-list as Denied' {
        Test-LicenseCompliance -License 'GPL-3.0' -AllowList $allowList -DenyList $denyList | Should -Be 'Denied'
    }

    It 'marks a license on neither list as Unknown' {
        Test-LicenseCompliance -License 'MPL-2.0' -AllowList $allowList -DenyList $denyList | Should -Be 'Unknown'
    }

    It 'marks the sentinel UNKNOWN license value as Unknown' {
        Test-LicenseCompliance -License 'UNKNOWN' -AllowList $allowList -DenyList $denyList | Should -Be 'Unknown'
    }

    It 'is case-insensitive when comparing license identifiers' {
        Test-LicenseCompliance -License 'mit' -AllowList $allowList -DenyList $denyList | Should -Be 'Approved'
    }
}
