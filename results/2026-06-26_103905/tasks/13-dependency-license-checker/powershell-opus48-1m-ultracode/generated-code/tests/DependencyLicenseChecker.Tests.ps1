# DependencyLicenseChecker.Tests.ps1
#
# Pester 5 unit tests for the dependency license checker module.
#
# TDD approach: each Describe block was written as a failing test first, then the
# minimum module code was added to make it pass (red -> green -> refactor).
#
# These tests are PURE unit tests (no Docker / no act). They are the tests the CI
# workflow's `validate` job runs inside the container, so they must stay
# self-contained: temp files only, no network, the external license lookup is
# mocked via Pester so no real registry is contacted.

BeforeAll {
    # Import the module under test with -Force so iterative TDD edits are picked up
    # on every run instead of a stale cached copy masking changes.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'DependencyLicenseChecker.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-LicenseStatus' {
    BeforeAll {
        # A representative policy used across the classification cases.
        $script:Policy = [pscustomobject]@{
            Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause', 'ISC')
            Deny  = @('GPL-3.0', 'AGPL-3.0', 'GPL-2.0')
        }
    }

    It 'returns "approved" for a license on the allow-list' {
        Get-LicenseStatus -License 'MIT' -Policy $script:Policy | Should -Be 'approved'
    }

    It 'returns "denied" for a license on the deny-list' {
        Get-LicenseStatus -License 'GPL-3.0' -Policy $script:Policy | Should -Be 'denied'
    }

    It 'returns "unknown" for a license on neither list' {
        Get-LicenseStatus -License 'WTFPL' -Policy $script:Policy | Should -Be 'unknown'
    }

    It 'returns "unknown" for a null or empty license' {
        Get-LicenseStatus -License $null -Policy $script:Policy | Should -Be 'unknown'
        Get-LicenseStatus -License '' -Policy $script:Policy | Should -Be 'unknown'
    }

    It 'lets the deny-list win when a license is on both lists (deny precedence)' {
        $conflict = [pscustomobject]@{ Allow = @('MIT', 'GPL-3.0'); Deny = @('GPL-3.0') }
        Get-LicenseStatus -License 'GPL-3.0' -Policy $conflict | Should -Be 'denied'
    }

    It 'matches license names case-insensitively' {
        Get-LicenseStatus -License 'mit' -Policy $script:Policy | Should -Be 'approved'
    }
}

Describe 'Get-DependencyList' {

    Context 'package.json (npm)' {
        BeforeAll {
            $script:Pkg = Join-Path $TestDrive 'package.json'
            @'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "~4.17.21"
  },
  "devDependencies": {
    "jest": ">=29.7.0"
  }
}
'@ | Set-Content -Path $script:Pkg -Encoding utf8
        }

        It 'extracts every dependency and devDependency' {
            $deps = Get-DependencyList -ManifestPath $script:Pkg
            $deps.Count | Should -Be 3
            $deps.Name | Should -Be @('express', 'lodash', 'jest')
        }

        It 'preserves manifest order (dependencies then devDependencies)' {
            $deps = Get-DependencyList -ManifestPath $script:Pkg
            $deps[0].Name | Should -Be 'express'
            $deps[2].Name | Should -Be 'jest'
        }

        It 'strips leading semver range operators from versions' {
            $deps = Get-DependencyList -ManifestPath $script:Pkg
            ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
            ($deps | Where-Object Name -eq 'lodash').Version  | Should -Be '4.17.21'
            ($deps | Where-Object Name -eq 'jest').Version     | Should -Be '29.7.0'
        }

        It 'reports the manifest type as npm' {
            $deps = Get-DependencyList -ManifestPath $script:Pkg
            $deps[0].Type | Should -Be 'npm'
        }
    }

    Context 'requirements.txt (pip)' {
        BeforeAll {
            $script:Req = Join-Path $TestDrive 'requirements.txt'
            @'
# a comment line that must be ignored
requests==2.31.0
flask>=2.0.0

numpy~=1.26.0
package-with-extras[security]==3.1.0
bare-package
'@ | Set-Content -Path $script:Req -Encoding utf8
        }

        It 'parses name and version, skipping comments and blank lines' {
            $deps = Get-DependencyList -ManifestPath $script:Req
            $deps.Name | Should -Be @('requests', 'flask', 'numpy', 'package-with-extras', 'bare-package')
        }

        It 'splits the version off the pip specifier operator' {
            $deps = Get-DependencyList -ManifestPath $script:Req
            ($deps | Where-Object Name -eq 'requests').Version | Should -Be '2.31.0'
            ($deps | Where-Object Name -eq 'flask').Version    | Should -Be '2.0.0'
            ($deps | Where-Object Name -eq 'numpy').Version     | Should -Be '1.26.0'
        }

        It 'strips extras like [security] from the package name' {
            $deps = Get-DependencyList -ManifestPath $script:Req
            ($deps | Where-Object Name -eq 'package-with-extras').Version | Should -Be '3.1.0'
        }

        It 'gives a bare (unpinned) package an empty version' {
            $deps = Get-DependencyList -ManifestPath $script:Req
            ($deps | Where-Object Name -eq 'bare-package').Version | Should -Be ''
        }

        It 'reports the manifest type as pip' {
            $deps = Get-DependencyList -ManifestPath $script:Req
            $deps[0].Type | Should -Be 'pip'
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the manifest does not exist' {
            { Get-DependencyList -ManifestPath (Join-Path $TestDrive 'nope.json') } |
                Should -Throw -ExpectedMessage '*not found*'
        }

        It 'throws a meaningful error for an unsupported manifest type' {
            $bad = Join-Path $TestDrive 'pom.xml'
            'x' | Set-Content -Path $bad -Encoding utf8
            { Get-DependencyList -ManifestPath $bad } | Should -Throw -ExpectedMessage '*Unsupported*'
        }

        It 'throws on malformed package.json' {
            $bad = Join-Path $TestDrive 'broken.json'
            '{ not valid json' | Set-Content -Path $bad -Encoding utf8
            { Get-DependencyList -ManifestPath $bad } | Should -Throw
        }
    }
}

Describe 'Read-LicensePolicy' {
    It 'reads allow and deny arrays from a JSON policy file' {
        $p = Join-Path $TestDrive 'policy.json'
        '{ "allow": ["MIT", "ISC"], "deny": ["GPL-3.0"] }' | Set-Content -Path $p -Encoding utf8
        $policy = Read-LicensePolicy -PolicyPath $p
        $policy.Allow | Should -Be @('MIT', 'ISC')
        $policy.Deny  | Should -Be @('GPL-3.0')
    }

    It 'defaults missing allow/deny keys to empty arrays' {
        $p = Join-Path $TestDrive 'policy-empty.json'
        '{ "allow": ["MIT"] }' | Set-Content -Path $p -Encoding utf8
        $policy = Read-LicensePolicy -PolicyPath $p
        $policy.Allow | Should -Be @('MIT')
        @($policy.Deny).Count | Should -Be 0
    }

    It 'throws a meaningful error when the policy file is missing' {
        { Read-LicensePolicy -PolicyPath (Join-Path $TestDrive 'no-policy.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Read-LicenseDatabase' {
    It 'loads a name -> license map into a lookup hashtable' {
        $p = Join-Path $TestDrive 'licenses.json'
        '{ "express": "MIT", "evil": "GPL-3.0" }' | Set-Content -Path $p -Encoding utf8
        $db = Read-LicenseDatabase -Path $p
        $db['express'] | Should -Be 'MIT'
        $db['evil']    | Should -Be 'GPL-3.0'
    }

    It 'throws a meaningful error when the database file is missing' {
        { Read-LicenseDatabase -Path (Join-Path $TestDrive 'no-db.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Resolve-DependencyLicense (the mockable lookup seam)' {
    BeforeAll {
        $script:Db = @{ express = 'MIT'; evil = 'GPL-3.0' }
    }

    It 'returns the license for a known package' {
        Resolve-DependencyLicense -Name 'express' -Version '4.18.2' -Database $script:Db | Should -Be 'MIT'
    }

    It 'returns $null for an unknown package' {
        Resolve-DependencyLicense -Name 'ghost' -Version '1.0.0' -Database $script:Db | Should -BeNullOrEmpty
    }
}

Describe 'Get-ComplianceReport' {
    BeforeAll {
        $script:Policy = [pscustomobject]@{
            Allow = @('MIT', 'Apache-2.0')
            Deny  = @('GPL-3.0')
        }
        $script:Deps = @(
            [pscustomobject]@{ Name = 'express'; Version = '4.18.2'; Type = 'npm' }
            [pscustomobject]@{ Name = 'evil';    Version = '1.0.0';  Type = 'npm' }
            [pscustomobject]@{ Name = 'mystery'; Version = '2.0.0';  Type = 'npm' }
        )
    }

    It 'classifies each dependency using the mocked license lookup' {
        # Mock the external license lookup at module scope so the internal call
        # inside Get-ComplianceReport is intercepted. This demonstrates the
        # required "mock the license lookup for testing" with no real registry.
        Mock -ModuleName DependencyLicenseChecker Resolve-DependencyLicense {
            switch ($Name) {
                'express' { 'MIT' }
                'evil'    { 'GPL-3.0' }
                default   { $null }
            }
        }

        $report = Get-ComplianceReport -Dependencies $script:Deps -Policy $script:Policy -Database @{}

        $report.Count | Should -Be 3
        ($report | Where-Object Name -eq 'express').Status | Should -Be 'approved'
        ($report | Where-Object Name -eq 'evil').Status    | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery').Status | Should -Be 'unknown'

        Should -Invoke -ModuleName DependencyLicenseChecker Resolve-DependencyLicense -Times 3 -Exactly
    }

    It 'labels an unresolved license as the literal "UNKNOWN"' {
        Mock -ModuleName DependencyLicenseChecker Resolve-DependencyLicense { $null }
        $report = Get-ComplianceReport -Dependencies $script:Deps -Policy $script:Policy -Database @{}
        ($report | Where-Object Name -eq 'mystery').License | Should -Be 'UNKNOWN'
    }

    It 'preserves the input dependency order in the report' {
        Mock -ModuleName DependencyLicenseChecker Resolve-DependencyLicense { 'MIT' }
        $report = Get-ComplianceReport -Dependencies $script:Deps -Policy $script:Policy -Database @{}
        $report.Name | Should -Be @('express', 'evil', 'mystery')
    }
}

Describe 'Get-ComplianceSummary' {
    It 'counts statuses and flags compliance only when nothing is denied or unknown' {
        $report = @(
            [pscustomobject]@{ Name = 'a'; Version = '1'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'b'; Version = '1'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'c'; Version = '1'; License = 'GPL-3.0'; Status = 'denied' }
            [pscustomobject]@{ Name = 'd'; Version = '1'; License = 'UNKNOWN'; Status = 'unknown' }
        )
        $s = Get-ComplianceSummary -Report $report
        $s.Approved  | Should -Be 2
        $s.Denied    | Should -Be 1
        $s.Unknown   | Should -Be 1
        $s.Total     | Should -Be 4
        $s.Compliant | Should -BeFalse
    }

    It 'is compliant when every dependency is approved' {
        $report = @(
            [pscustomobject]@{ Name = 'a'; Version = '1'; License = 'MIT'; Status = 'approved' }
            [pscustomobject]@{ Name = 'b'; Version = '1'; License = 'ISC'; Status = 'approved' }
        )
        $s = Get-ComplianceSummary -Report $report
        $s.Compliant | Should -BeTrue
        $s.Approved  | Should -Be 2
    }

    It 'handles an empty report (vacuously compliant)' {
        $s = Get-ComplianceSummary -Report @()
        $s.Total     | Should -Be 0
        $s.Compliant | Should -BeTrue
    }
}

Describe 'Format-ComplianceReport' {
    BeforeAll {
        $script:Report = @(
            [pscustomobject]@{ Name = 'express'; Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'evil';    Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied' }
            [pscustomobject]@{ Name = 'mystery'; Version = '2.0.0';  License = 'UNKNOWN'; Status = 'unknown' }
        )
        $script:Summary = [pscustomobject]@{
            Approved = 1; Denied = 1; Unknown = 1; Total = 3; Compliant = $false
        }
    }

    It 'emits deterministic, parseable text lines' {
        $text = Format-ComplianceReport -Report $script:Report -Summary $script:Summary -Format text
        $text | Should -Match 'DEP name=express version=4.18.2 license=MIT status=approved'
        $text | Should -Match 'DEP name=evil version=1.0.0 license=GPL-3.0 status=denied'
        $text | Should -Match 'DEP name=mystery version=2.0.0 license=UNKNOWN status=unknown'
        $text | Should -Match 'RESULT approved=1 denied=1 unknown=1 total=3'
        $text | Should -Match 'COMPLIANCE: NON-COMPLIANT'
    }

    It 'emits a COMPLIANT verdict when the summary is compliant' {
        $summary = [pscustomobject]@{ Approved = 3; Denied = 0; Unknown = 0; Total = 3; Compliant = $true }
        $text = Format-ComplianceReport -Report $script:Report -Summary $summary -Format text
        $text | Should -Match 'COMPLIANCE: COMPLIANT'
    }

    It 'emits a GitHub-flavoured markdown table' {
        $md = Format-ComplianceReport -Report $script:Report -Summary $script:Summary -Format markdown
        $md | Should -Match '\| Dependency \| Version \| License \| Status \|'
        $md | Should -Match '\| express \| 4.18.2 \| MIT \| approved \|'
        $md | Should -Match 'NON-COMPLIANT'
    }

    It 'emits valid JSON round-trippable back to the report rows' {
        $json = Format-ComplianceReport -Report $script:Report -Summary $script:Summary -Format json
        $obj = $json | ConvertFrom-Json
        $obj.summary.denied | Should -Be 1
        $obj.dependencies.Count | Should -Be 3
        $obj.dependencies[0].name | Should -Be 'express'
    }
}
