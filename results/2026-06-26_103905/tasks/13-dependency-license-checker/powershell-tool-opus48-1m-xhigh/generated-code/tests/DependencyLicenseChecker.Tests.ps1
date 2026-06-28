# Pester unit tests for the Dependency License Checker.
#
# TDD approach: each Describe block was written test-first (red), then the matching
# function in ../DependencyLicenseChecker.ps1 was implemented to make it pass
# (green), then refactored. The script is dot-sourced so its functions are
# available here; a guard in the script prevents its "main" body running on
# dot-source.

BeforeAll {
    $script:ScriptPath = "$PSScriptRoot/../DependencyLicenseChecker.ps1"
    . $script:ScriptPath

    $script:RepoRoot  = (Resolve-Path "$PSScriptRoot/..").Path
    $script:Fixtures  = Join-Path $script:RepoRoot 'fixtures'
    $script:CfgPath = Join-Path $script:RepoRoot 'license-config.json'
    $script:DbPath     = Join-Path $script:RepoRoot 'license-db.json'
}

Describe 'Get-LicenseStatus' {
    It 'returns approved when the license is on the allow-list' {
        Get-LicenseStatus -License 'MIT' -AllowList @('MIT', 'ISC') -DenyList @('GPL-3.0') |
            Should -Be 'approved'
    }

    It 'returns denied when the license is on the deny-list' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'denied'
    }

    It 'returns unknown when the license is on neither list' {
        Get-LicenseStatus -License 'WTFPL' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'unknown'
    }

    It 'returns unknown when the license is null or empty' {
        Get-LicenseStatus -License $null -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'unknown'
        Get-LicenseStatus -License '' -AllowList @('MIT') -DenyList @('GPL-3.0') |
            Should -Be 'unknown'
    }

    It 'lets deny win over allow when a license is on both lists (fail closed)' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList @('GPL-3.0') -DenyList @('GPL-3.0') |
            Should -Be 'denied'
    }
}

Describe 'Read-DependencyManifest (package.json)' {
    It 'extracts names and versions from dependencies and devDependencies' {
        $deps = @(Read-DependencyManifest -Path (Join-Path $Fixtures 'clean/package.json'))
        $deps.Count | Should -Be 3
        ($deps | Where-Object Name -eq 'express').Version  | Should -Be '^4.18.2'
        ($deps | Where-Object Name -eq 'lodash').Version   | Should -Be '4.17.21'
        ($deps | Where-Object Name -eq 'chalk').Version    | Should -Be '5.3.0'
    }
}

Describe 'Read-DependencyManifest (requirements.txt)' {
    It 'parses name/version, skipping comments, options and markers' {
        $deps = @(Read-DependencyManifest -Path (Join-Path $Fixtures 'requirements/requirements.txt'))
        $deps.Count | Should -Be 5
        ($deps | Where-Object Name -eq 'requests').Version   | Should -Be '2.31.0'
        ($deps | Where-Object Name -eq 'flask').Version      | Should -Be '2.0.0'
        ($deps | Where-Object Name -eq 'gpl-py').Version     | Should -Be '1.2.3'
        ($deps | Where-Object Name -eq 'django').Version     | Should -Be '4.2.0'
        ($deps | Where-Object Name -eq 'unknown-py').Version | Should -Be '0.1.0'
    }
}

Describe 'Read-DependencyManifest (errors)' {
    It 'throws a meaningful error when the manifest does not exist' {
        { Read-DependencyManifest -Path (Join-Path $Fixtures 'nope/package.json') } |
            Should -Throw -ExpectedMessage '*Manifest file not found*'
    }

    It 'throws a meaningful error for an unsupported manifest type' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("manifest-{0}.cfg" -f ([guid]::NewGuid()))
        Set-Content -LiteralPath $tmp -Value 'whatever'
        try {
            { Read-DependencyManifest -Path $tmp } | Should -Throw -ExpectedMessage '*Unsupported manifest type*'
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error for malformed JSON' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("package-{0}.json" -f ([guid]::NewGuid()))
        Set-Content -LiteralPath $tmp -Value '{ this is not json'
        try {
            { Read-DependencyManifest -Path $tmp } | Should -Throw -ExpectedMessage '*Failed to parse package.json*'
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Read-LicenseConfig' {
    It 'loads the allow-list and deny-list arrays' {
        $cfg = Read-LicenseConfig -Path $CfgPath
        $cfg.AllowList | Should -Contain 'MIT'
        $cfg.AllowList | Should -Contain 'Apache-2.0'
        $cfg.DenyList  | Should -Contain 'GPL-3.0'
        $cfg.DenyList  | Should -Contain 'AGPL-3.0'
    }

    It 'throws when the config file is missing' {
        { Read-LicenseConfig -Path (Join-Path $RepoRoot 'no-such-config.json') } |
            Should -Throw -ExpectedMessage '*License config file not found*'
    }
}

Describe 'Get-DependencyLicense (database-backed lookup)' {
    BeforeAll {
        $script:Db = Read-LicenseDatabase -Path $DbPath
    }

    It 'returns the mapped license for a known dependency' {
        Get-DependencyLicense -Name 'express' -Database $Db | Should -Be 'MIT'
        Get-DependencyLicense -Name 'gpl-py'  -Database $Db | Should -Be 'GPL-2.0'
    }

    It 'returns $null for a dependency missing from the database' {
        Get-DependencyLicense -Name 'does-not-exist' -Database $Db | Should -BeNullOrEmpty
    }

    It 'returns $null when the database maps the name to null' {
        Get-DependencyLicense -Name 'mystery-box' -Database $Db | Should -BeNullOrEmpty
    }
}

Describe 'New-ComplianceReport (with mocked license lookup)' {
    # Demonstrates mocking the license lookup, per the task requirement.
    # The Mock is declared inside each It so it is torn down immediately after and
    # cannot leak into the real-lookup tests further down the file.
    It 'classifies each dependency and computes summary counts' {
        Mock Get-DependencyLicense {
            switch ($Name) {
                'good-pkg' { 'MIT' }
                'bad-pkg'  { 'GPL-3.0' }
                'odd-pkg'  { 'WTFPL' }   # known but unclassified -> unknown
                default    { $null }      # everything else -> unknown
            }
        }

        $deps = @(
            [pscustomobject]@{ Name = 'good-pkg';     Version = '1.0.0' }
            [pscustomobject]@{ Name = 'bad-pkg';      Version = '2.0.0' }
            [pscustomobject]@{ Name = 'odd-pkg';      Version = '3.0.0' }
            [pscustomobject]@{ Name = 'missing-pkg';  Version = '4.0.0' }
        )

        $report = New-ComplianceReport -Dependencies $deps `
            -AllowList @('MIT') -DenyList @('GPL-3.0')

        $report.Summary.Total    | Should -Be 4
        $report.Summary.Approved | Should -Be 1
        $report.Summary.Denied   | Should -Be 1
        $report.Summary.Unknown  | Should -Be 2
        $report.Compliant        | Should -BeFalse

        ($report.Dependencies | Where-Object Name -eq 'good-pkg').Status | Should -Be 'approved'
        ($report.Dependencies | Where-Object Name -eq 'bad-pkg').Status  | Should -Be 'denied'

        # The mock was actually used.
        Should -Invoke Get-DependencyLicense -Times 4 -Exactly
    }

    It 'reports Compliant = $true when nothing is denied' {
        Mock Get-DependencyLicense {
            switch ($Name) {
                'good-pkg' { 'MIT' }
                default    { $null }
            }
        }
        $deps = @([pscustomobject]@{ Name = 'good-pkg'; Version = '1.0.0' })
        $report = New-ComplianceReport -Dependencies $deps -AllowList @('MIT') -DenyList @('GPL-3.0')
        $report.Compliant      | Should -BeTrue
        $report.Summary.Denied | Should -Be 0
    }
}

Describe 'Format-ComplianceReport' {
    BeforeAll {
        $script:Report = [pscustomobject]@{
            Dependencies = @(
                [pscustomobject]@{ Name = 'express';      Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
                [pscustomobject]@{ Name = 'copyleft-lib'; Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied'   }
                [pscustomobject]@{ Name = 'mystery-box';  Version = '0.0.1';  License = $null;     Status = 'unknown'  }
            )
            Summary   = [pscustomobject]@{ Total = 3; Approved = 1; Denied = 1; Unknown = 1 }
            Compliant = $false
        }
    }

    It 'summary format emits a single stable RESULT line' {
        $out = Format-ComplianceReport -Report $Report -Format 'summary' -Label 'demo'
        $out | Should -Be 'RESULT label=demo total=3 approved=1 denied=1 unknown=1 compliant=false'
    }

    It 'json format round-trips back to the same summary numbers' {
        $out = Format-ComplianceReport -Report $Report -Format 'json'
        $parsed = $out | ConvertFrom-Json
        $parsed.Summary.Total  | Should -Be 3
        $parsed.Summary.Denied | Should -Be 1
        $parsed.Compliant      | Should -BeFalse
    }

    It 'markdown format includes a table row per dependency and the RESULT line' {
        $out = Format-ComplianceReport -Report $Report -Format 'markdown'
        $out | Should -Match '\| express \| 4.18.2 \| MIT \| approved \|'
        $out | Should -Match '\(unknown\)'
        $out | Should -Match 'RESULT label= total=3 approved=1 denied=1 unknown=1 compliant=false'
    }
}

Describe 'Invoke-LicenseCheck (end-to-end against fixtures)' {
    It 'reports the clean fixture as fully approved and compliant' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'clean/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -Label 'clean'
        $r.IsError  | Should -BeFalse
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Be 'RESULT label=clean total=3 approved=3 denied=0 unknown=0 compliant=true'
    }

    It 'reports the violations fixture with two denied deps' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'violations/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -Label 'violations'
        $r.Output | Should -Be 'RESULT label=violations total=3 approved=1 denied=2 unknown=0 compliant=false'
    }

    It 'reports the mixed fixture with approved/denied/unknown' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'mixed/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -Label 'mixed'
        $r.Output | Should -Be 'RESULT label=mixed total=4 approved=1 denied=1 unknown=2 compliant=false'
    }

    It 'reports the requirements.txt fixture correctly' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'requirements/requirements.txt') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -Label 'requirements'
        $r.Output | Should -Be 'RESULT label=requirements total=5 approved=3 denied=1 unknown=1 compliant=false'
    }

    It 'exits 1 with -FailOnViolation when a denied dependency is present' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'violations/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -FailOnViolation
        $r.ExitCode | Should -Be 1
    }

    It 'exits 0 with -FailOnViolation when everything is compliant' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'clean/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath -Format 'summary' -FailOnViolation
        $r.ExitCode | Should -Be 0
    }

    It 'returns a meaningful error (exit 2) for a missing manifest' {
        $r = Invoke-LicenseCheck -ManifestPath (Join-Path $Fixtures 'nope/package.json') `
            -ConfigPath $CfgPath -LicenseDbPath $DbPath
        $r.IsError  | Should -BeTrue
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -Match 'Manifest file not found'
    }
}
