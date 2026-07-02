# Red/Green TDD - Step 3: config loading + end-to-end compliance report.

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'LicenseChecker.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-LicensePolicy' {
    It 'loads the allow-list and deny-list from a JSON config file' {
        $configPath = Join-Path $PSScriptRoot '..' 'fixtures' 'license-policy.json'
        $policy = Get-LicensePolicy -Path $configPath
        $policy.AllowList | Should -Contain 'MIT'
        $policy.DenyList | Should -Contain 'GPL-3.0'
    }

    It 'throws a meaningful error when the policy file does not exist' {
        { Get-LicensePolicy -Path 'no-such-policy.json' } | Should -Throw '*not found*'
    }
}

Describe 'New-ComplianceReport' {
    BeforeAll {
        Clear-MockPackageLicense
        Set-MockPackageLicense -Name 'lodash' -Version '4.17.21' -License 'MIT'
        Set-MockPackageLicense -Name 'express' -Version '4.18.2' -License 'GPL-3.0'
        # 'jest' and 'eslint' are intentionally left unmocked -> UNKNOWN license

        $manifestPath = Join-Path $PSScriptRoot '..' 'fixtures' 'package.json'
        $policyPath = Join-Path $PSScriptRoot '..' 'fixtures' 'license-policy.json'
        $policy = Get-LicensePolicy -Path $policyPath
        $deps = Get-DependenciesFromManifest -Path $manifestPath

        $script:report = New-ComplianceReport -Dependencies $deps -Policy $policy
    }

    It 'produces one report entry per dependency' {
        $script:report.Count | Should -Be 4
    }

    It 'marks an allow-listed license dependency as Approved' {
        ($script:report | Where-Object Name -eq 'lodash').Status | Should -Be 'Approved'
    }

    It 'marks a deny-listed license dependency as Denied' {
        ($script:report | Where-Object Name -eq 'express').Status | Should -Be 'Denied'
    }

    It 'marks a dependency with no license data as Unknown' {
        ($script:report | Where-Object Name -eq 'jest').Status | Should -Be 'Unknown'
    }

    It 'includes the resolved license string for each dependency' {
        ($script:report | Where-Object Name -eq 'lodash').License | Should -Be 'MIT'
    }
}
