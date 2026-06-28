<#
.SYNOPSIS
    Pester unit tests for the Dependency License Checker.

.DESCRIPTION
    These tests drive the implementation in DependencyLicenseChecker.ps1 using
    red/green TDD. The script is dot-sourced (its CLI body is guarded so that
    dot-sourcing only defines functions), making each function unit-testable.

    The "license lookup" (Get-DependencyLicense) is the test seam: it is mocked
    with Pester's Mock so that report-generation logic can be exercised
    deterministically without a real license source — satisfying the task's
    "Mock the license lookup for testing" requirement.
#>

BeforeAll {
    # Dot-source the script under test. The guard at the bottom of the script
    # prevents the CLI body from running when the file is dot-sourced (.).
    . "$PSScriptRoot/DependencyLicenseChecker.ps1"

    # A small temp workspace for fixture files created during tests.
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dlc-tests-$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    # Helper to write a fixture file and return its path.
    function script:New-Fixture {
        param([string]$Name, [string]$Content)
        $p = Join-Path $script:TempDir $Name
        $Content | Set-Content -LiteralPath $p -Encoding utf8
        return $p
    }
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Recurse -Force $script:TempDir
    }
}

Describe 'Get-Dependencies (package.json)' {
    It 'extracts names and versions from a package.json dependencies block' {
        $pkg = New-Fixture 'package.json' @'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "4.17.21"
  }
}
'@
        $deps = Get-Dependencies -ManifestPath $pkg
        $deps | Should -HaveCount 2
        ($deps | Where-Object Name -eq 'express').Version | Should -Be '4.18.2'
        ($deps | Where-Object Name -eq 'lodash').Version  | Should -Be '4.17.21'
    }

    It 'includes devDependencies as well as dependencies' {
        $pkg = New-Fixture 'pkg-dev.json' @'
{
  "dependencies":    { "express": "~4.18.0" },
  "devDependencies": { "jest": ">=29.0.0" }
}
'@
        $deps = Get-Dependencies -ManifestPath $pkg
        $deps.Name | Should -Contain 'express'
        $deps.Name | Should -Contain 'jest'
        ($deps | Where-Object Name -eq 'jest').Version | Should -Be '29.0.0'
    }

    It 'returns an empty set when there are no dependencies' {
        $pkg = New-Fixture 'pkg-empty.json' '{ "name": "x", "version": "1.0.0" }'
        $deps = Get-Dependencies -ManifestPath $pkg
        @($deps) | Should -HaveCount 0
    }
}

Describe 'Get-Dependencies (requirements.txt)' {
    It 'parses pinned, ranged and bare requirements while ignoring noise' {
        $req = New-Fixture 'requirements.txt' @'
# project requirements
requests==2.28.1
flask>=2.0
numpy
django==4.1.0  # inline comment
-r other-requirements.txt
requests[security]==2.28.1
celery==5.2.7 ; python_version >= "3.8"
'@
        $deps = Get-Dependencies -ManifestPath $req

        ($deps | Where-Object Name -eq 'requests').Version | Should -Contain '2.28.1'
        ($deps | Where-Object Name -eq 'flask').Version     | Should -Be '2.0'
        ($deps | Where-Object Name -eq 'numpy').Version     | Should -Be ''
        ($deps | Where-Object Name -eq 'django').Version    | Should -Be '4.1.0'
        ($deps | Where-Object Name -eq 'celery').Version    | Should -Be '5.2.7'
        # The "-r other-requirements.txt" options line must be skipped.
        $deps.Name | Should -Not -Contain 'other-requirements.txt'
        # The extras suffix is stripped from the name.
        $deps.Name | Should -Not -Contain 'requests[security]'
    }
}

Describe 'Get-Dependencies (error handling)' {
    It 'throws a clear error when the manifest does not exist' {
        { Get-Dependencies -ManifestPath (Join-Path $script:TempDir 'nope.json') } |
            Should -Throw '*Manifest file not found*'
    }

    It 'throws a clear error for an unsupported manifest type' {
        $bad = New-Fixture 'manifest.cfg' 'whatever'
        { Get-Dependencies -ManifestPath $bad } | Should -Throw '*Unsupported manifest type*'
    }

    It 'throws a clear error for invalid package.json JSON' {
        $bad = New-Fixture 'broken.json' '{ this is not json'
        { Get-Dependencies -ManifestPath $bad } | Should -Throw '*Failed to parse package.json*'
    }
}

Describe 'Get-DependencyLicense (default lookup)' {
    It 'returns the license from the database when present' {
        $db = @{ express = 'MIT' }
        Get-DependencyLicense -Name 'express' -LicenseDatabase $db | Should -Be 'MIT'
    }
    It 'returns $null when the dependency is unknown' {
        $db = @{ express = 'MIT' }
        Get-DependencyLicense -Name 'mystery' -LicenseDatabase $db | Should -BeNullOrEmpty
    }
}

Describe 'Get-LicenseStatus (classification)' {
    BeforeAll {
        $script:Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause')
        $script:Deny  = @('GPL-3.0', 'AGPL-3.0')
    }
    It 'classifies an allow-listed license as approved' {
        Get-LicenseStatus -License 'MIT' -AllowList $Allow -DenyList $Deny | Should -Be 'approved'
    }
    It 'classifies a deny-listed license as denied' {
        Get-LicenseStatus -License 'GPL-3.0' -AllowList $Allow -DenyList $Deny | Should -Be 'denied'
    }
    It 'classifies an unresolved (null/empty) license as unknown' {
        Get-LicenseStatus -License $null -AllowList $Allow -DenyList $Deny | Should -Be 'unknown'
        Get-LicenseStatus -License ''   -AllowList $Allow -DenyList $Deny | Should -Be 'unknown'
    }
    It 'classifies a resolved-but-unclassified license as unknown' {
        Get-LicenseStatus -License 'WTFPL' -AllowList $Allow -DenyList $Deny | Should -Be 'unknown'
    }
    It 'gives deny precedence when a license is on both lists' {
        Get-LicenseStatus -License 'MIT' -AllowList @('MIT') -DenyList @('MIT') | Should -Be 'denied'
    }
}

Describe 'New-ComplianceReport (with MOCKED license lookup)' {
    BeforeAll {
        $script:deps = @(
            [pscustomobject]@{ Name = 'express'; Version = '4.18.2' }
            [pscustomobject]@{ Name = 'gpl-lib'; Version = '1.0.0' }
            [pscustomobject]@{ Name = 'mystery'; Version = '2.1.0' }
        )
        $script:Allow = @('MIT', 'Apache-2.0')
        $script:Deny  = @('GPL-3.0')
    }

    It 'resolves each dependency via the (mocked) lookup and classifies it' {
        # Mock the license lookup so no real source is consulted.
        Mock Get-DependencyLicense { 'MIT' }      -ParameterFilter { $Name -eq 'express' }
        Mock Get-DependencyLicense { 'GPL-3.0' }  -ParameterFilter { $Name -eq 'gpl-lib' }
        Mock Get-DependencyLicense { $null }       -ParameterFilter { $Name -eq 'mystery' }

        $report = New-ComplianceReport -Dependencies $deps -AllowList $Allow -DenyList $Deny

        ($report | Where-Object Name -eq 'express').Status | Should -Be 'approved'
        ($report | Where-Object Name -eq 'gpl-lib').Status | Should -Be 'denied'
        ($report | Where-Object Name -eq 'mystery').Status | Should -Be 'unknown'
        # Unknown license is rendered as the literal 'UNKNOWN'.
        ($report | Where-Object Name -eq 'mystery').License | Should -Be 'UNKNOWN'

        # The lookup seam was actually invoked once per dependency.
        Should -Invoke Get-DependencyLicense -Times 3 -Exactly
    }
}

Describe 'Get-ComplianceSummary' {
    It 'counts totals per status' {
        $report = @(
            [pscustomobject]@{ Status = 'approved' }
            [pscustomobject]@{ Status = 'approved' }
            [pscustomobject]@{ Status = 'denied' }
            [pscustomobject]@{ Status = 'unknown' }
        )
        $s = Get-ComplianceSummary -Report $report
        $s.Total    | Should -Be 4
        $s.Approved | Should -Be 2
        $s.Denied   | Should -Be 1
        $s.Unknown  | Should -Be 1
    }
}

Describe 'Format-ComplianceReport' {
    BeforeAll {
        $script:report = @(
            [pscustomobject]@{ Name = 'express'; Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
            [pscustomobject]@{ Name = 'gpl-lib'; Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied' }
            [pscustomobject]@{ Name = 'mystery'; Version = '2.1.0';  License = 'UNKNOWN'; Status = 'unknown' }
        )
    }

    It 'renders stable Text lines and an exact summary line' {
        $text = Format-ComplianceReport -Report $report -Format Text
        $text | Should -Match '\[APPROVED\] express@4\.18\.2 -> MIT'
        $text | Should -Match '\[DENIED\] gpl-lib@1\.0\.0 -> GPL-3\.0'
        $text | Should -Match '\[UNKNOWN\] mystery@2\.1\.0 -> UNKNOWN'
        $text | Should -Match 'Summary: total=3 approved=1 denied=1 unknown=1'
        $text | Should -Match 'Result: NON-COMPLIANT'
    }

    It 'reports COMPLIANT when there are no denied dependencies' {
        $clean = @([pscustomobject]@{ Name = 'a'; Version = '1'; License = 'MIT'; Status = 'approved' })
        (Format-ComplianceReport -Report $clean -Format Text) | Should -Match 'Result: COMPLIANT'
    }

    It 'renders valid JSON with dependencies, summary and result' {
        $json = Format-ComplianceReport -Report $report -Format Json | ConvertFrom-Json
        $json.summary.total  | Should -Be 3
        $json.summary.denied | Should -Be 1
        $json.result         | Should -Be 'NON-COMPLIANT'
        $json.dependencies   | Should -HaveCount 3
    }

    It 'renders a Markdown table for the job summary' {
        $md = Format-ComplianceReport -Report $report -Format Markdown
        $md | Should -Match '\| Dependency \| Version \| License \| Status \|'
        $md | Should -Match '\| express \| 4\.18\.2 \| MIT \| APPROVED \|'
        $md | Should -Match '\*\*Result:\*\* NON-COMPLIANT'
    }
}

Describe 'Get-CheckerConfig' {
    It 'loads allow/deny lists and optional fields' {
        $cfg = New-Fixture 'config.json' @'
{
  "manifest": "examples/package.json",
  "licenseDb": "examples/licenses.json",
  "allow": ["MIT", "Apache-2.0"],
  "deny": ["GPL-3.0"],
  "failOnViolation": true
}
'@
        $c = Get-CheckerConfig -ConfigPath $cfg
        $c.Allow           | Should -Contain 'MIT'
        $c.Deny            | Should -Contain 'GPL-3.0'
        $c.Manifest        | Should -Be 'examples/package.json'
        $c.LicenseDb       | Should -Be 'examples/licenses.json'
        $c.FailOnViolation | Should -BeTrue
    }

    It 'throws a clear error when the config is missing' {
        { Get-CheckerConfig -ConfigPath (Join-Path $script:TempDir 'no-config.json') } |
            Should -Throw '*Config file not found*'
    }
}

Describe 'Import-LicenseDatabase' {
    It 'loads a name->license map into a hashtable' {
        $db = New-Fixture 'licenses.json' '{ "express": "MIT", "gpl-lib": "GPL-3.0" }'
        $h = Import-LicenseDatabase -LicenseDbPath $db
        $h['express'] | Should -Be 'MIT'
        $h['gpl-lib'] | Should -Be 'GPL-3.0'
    }
    It 'returns an empty hashtable when no path is given' {
        (Import-LicenseDatabase -LicenseDbPath '').Count | Should -Be 0
    }
}

Describe 'Invoke-LicenseCheck (end-to-end, real license DB)' {
    It 'produces a correct report from a manifest + config + license DB' {
        $manifest = New-Fixture 'e2e-package.json' @'
{
  "dependencies": {
    "express": "^4.18.2",
    "gpl-lib": "1.0.0",
    "mystery-pkg": "2.1.0"
  }
}
'@
        $licDb = New-Fixture 'e2e-licenses.json' '{ "express": "MIT", "gpl-lib": "GPL-3.0" }'
        $config = New-Fixture 'e2e-config.json' @"
{
  "manifest": "$($manifest -replace '\\','/')",
  "licenseDb": "$($licDb -replace '\\','/')",
  "allow": ["MIT", "Apache-2.0"],
  "deny": ["GPL-3.0"]
}
"@
        $outcome = Invoke-LicenseCheck -ConfigPath $config -Format Text

        $outcome.Summary.Total    | Should -Be 3
        $outcome.Summary.Approved | Should -Be 1
        $outcome.Summary.Denied   | Should -Be 1
        $outcome.Summary.Unknown  | Should -Be 1
        $outcome.Rendered | Should -Match 'Summary: total=3 approved=1 denied=1 unknown=1'
        $outcome.Rendered | Should -Match 'Result: NON-COMPLIANT'
    }

    It 'throws a clear error when no manifest is configured' {
        $config = New-Fixture 'no-manifest-config.json' '{ "allow": ["MIT"], "deny": [] }'
        { Invoke-LicenseCheck -ConfigPath $config } | Should -Throw '*No manifest specified*'
    }
}
