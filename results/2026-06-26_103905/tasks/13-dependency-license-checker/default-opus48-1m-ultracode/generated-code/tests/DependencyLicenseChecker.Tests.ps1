<#
    Pester 5 unit tests for the DependencyLicenseChecker module.

    Methodology: red/green TDD. Each Describe/It block was written BEFORE the
    code that satisfies it. The license lookup is mocked so tests never touch
    the filesystem-backed license database or any network.
#>

BeforeAll {
    # Resolve the module relative to this test file so it works from any CWD
    # (local dev, CI container, act, etc.).
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'DependencyLicenseChecker.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Read-DependencyManifest (package.json / npm)' {

    It 'extracts name and normalized version for each runtime dependency' {
        $manifest = @'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "~4.17.21"
  }
}
'@
        $path = Join-Path $TestDrive 'package.json'
        Set-Content -Path $path -Value $manifest -Encoding utf8

        $deps = Read-DependencyManifest -Path $path

        $deps | Should -HaveCount 2
        # Results are sorted by name for deterministic output.
        $deps[0].Name    | Should -Be 'express'
        $deps[0].Version | Should -Be '4.18.2'   # range operator stripped
        $deps[1].Name    | Should -Be 'lodash'
        $deps[1].Version | Should -Be '4.17.21'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Read-DependencyManifest -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error on malformed JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $path -Value '{ this is not json' -Encoding utf8
        { Read-DependencyManifest -Path $path } |
            Should -Throw -ExpectedMessage '*Failed to parse JSON*'
    }
}

Describe 'Read-DependencyManifest (requirements.txt / pip)' {

    It 'parses pinned and ranged requirements, ignoring comments and blanks' {
        $reqs = @'
# project requirements
requests==2.31.0
PyYAML>=6.0

# a comment
internal-thing
'@
        $path = Join-Path $TestDrive 'requirements.txt'
        Set-Content -Path $path -Value $reqs -Encoding utf8

        $deps = Read-DependencyManifest -Path $path

        $deps | Should -HaveCount 3
        # Sorted by canonical (lower-cased) name.
        $deps[0].Name    | Should -Be 'internal-thing'
        $deps[0].Version | Should -Be ''          # unpinned -> empty version
        $deps[1].Name    | Should -Be 'pyyaml'    # name canonicalized
        $deps[1].Version | Should -Be '6.0'       # operator stripped
        $deps[2].Name    | Should -Be 'requests'
        $deps[2].Version | Should -Be '2.31.0'
    }

    It 'strips extras such as requests[security]==2.31.0' {
        $path = Join-Path $TestDrive 'extras.txt'
        Set-Content -Path $path -Value 'requests[security]==2.31.0' -Encoding utf8

        $deps = Read-DependencyManifest -Path $path
        $deps | Should -HaveCount 1
        $deps[0].Name    | Should -Be 'requests'
        $deps[0].Version | Should -Be '2.31.0'
    }
}

Describe 'Get-LicenseStatus (policy classification)' {

    BeforeAll {
        $script:Policy = [pscustomobject]@{
            Allow = @('MIT', 'Apache-2.0', 'BSD-3-Clause', 'ISC')
            Deny  = @('GPL-3.0', 'AGPL-3.0', 'GPL-2.0')
        }
    }

    It "returns 'approved' for an allow-listed license" {
        Get-LicenseStatus -License 'MIT' -Policy $script:Policy | Should -Be 'approved'
    }

    It "returns 'denied' for a deny-listed license" {
        Get-LicenseStatus -License 'GPL-3.0' -Policy $script:Policy | Should -Be 'denied'
    }

    It "returns 'unknown' for a license in neither list" {
        Get-LicenseStatus -License 'MPL-2.0' -Policy $script:Policy | Should -Be 'unknown'
    }

    It "returns 'unknown' when the license is null or empty" {
        Get-LicenseStatus -License $null -Policy $script:Policy | Should -Be 'unknown'
        Get-LicenseStatus -License ''    -Policy $script:Policy | Should -Be 'unknown'
    }

    It 'matches licenses case-insensitively' {
        Get-LicenseStatus -License 'mit'     -Policy $script:Policy | Should -Be 'approved'
        Get-LicenseStatus -License 'gpl-3.0' -Policy $script:Policy | Should -Be 'denied'
    }

    It 'gives the deny-list precedence over the allow-list' {
        $conflict = [pscustomobject]@{ Allow = @('MIT'); Deny = @('MIT') }
        Get-LicenseStatus -License 'MIT' -Policy $conflict | Should -Be 'denied'
    }
}

Describe 'Get-DependencyLicense (license lookup)' {

    BeforeAll {
        # A small in-memory stand-in for a real license registry.
        $script:Db = @{ 'express' = 'MIT'; 'gpl-tool' = 'GPL-3.0' }
    }

    It 'returns the license recorded for a known dependency' {
        Get-DependencyLicense -Name 'express' -Database $script:Db | Should -Be 'MIT'
    }

    It 'looks dependencies up case-insensitively' {
        Get-DependencyLicense -Name 'EXPRESS' -Database $script:Db | Should -Be 'MIT'
    }

    It 'returns $null for an unknown dependency' {
        Get-DependencyLicense -Name 'no-such-pkg' -Database $script:Db | Should -BeNullOrEmpty
    }
}

Describe 'Import-LicenseDatabase' {

    It 'loads a JSON name->license map into a case-insensitive lookup' {
        $path = Join-Path $TestDrive 'licenses.json'
        Set-Content -Path $path -Encoding utf8 -Value '{ "express": "MIT", "Gpl-Tool": "GPL-3.0" }'

        $db = Import-LicenseDatabase -Path $path

        Get-DependencyLicense -Name 'express'  -Database $db | Should -Be 'MIT'
        Get-DependencyLicense -Name 'gpl-tool' -Database $db | Should -Be 'GPL-3.0'
    }

    It 'throws a meaningful error when the database file is missing' {
        { Import-LicenseDatabase -Path (Join-Path $TestDrive 'absent.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'New-ComplianceReport (orchestration, mocked lookup)' {

    BeforeAll {
        $script:Policy = [pscustomobject]@{
            Allow = @('MIT', 'Apache-2.0')
            Deny  = @('GPL-3.0')
        }

        $manifest = @'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "gpl-tool": "1.0.0",
    "mystery-lib": "0.0.1"
  }
}
'@
        $script:ManifestPath = Join-Path $TestDrive 'package.json'
        Set-Content -Path $script:ManifestPath -Value $manifest -Encoding utf8
    }

    BeforeEach {
        # MOCK the license lookup so the report logic is tested in isolation,
        # with no dependency on any real database or network.
        Mock -ModuleName DependencyLicenseChecker Get-DependencyLicense -MockWith {
            param($Name, $Database)
            switch ($Name) {
                'express'  { 'MIT' }
                'gpl-tool' { 'GPL-3.0' }
                default    { $null }      # mystery-lib -> unknown
            }
        }
    }

    It 'classifies every dependency and produces an accurate summary' {
        $report = New-ComplianceReport -ManifestPath $script:ManifestPath `
                                       -Policy $script:Policy -Database @{}

        $report.Entries | Should -HaveCount 3

        # Entries are sorted by name.
        $report.Entries[0].Name    | Should -Be 'express'
        $report.Entries[0].Version | Should -Be '4.18.2'
        $report.Entries[0].License | Should -Be 'MIT'
        $report.Entries[0].Status  | Should -Be 'approved'

        $report.Entries[1].Name    | Should -Be 'gpl-tool'
        $report.Entries[1].License | Should -Be 'GPL-3.0'
        $report.Entries[1].Status  | Should -Be 'denied'

        $report.Entries[2].Name    | Should -Be 'mystery-lib'
        $report.Entries[2].License | Should -BeNullOrEmpty
        $report.Entries[2].Status  | Should -Be 'unknown'

        $report.Summary.Approved | Should -Be 1
        $report.Summary.Denied   | Should -Be 1
        $report.Summary.Unknown  | Should -Be 1
        $report.Summary.Total    | Should -Be 3

        # Overall result fails because a denied license is present.
        $report.Result | Should -Be 'FAIL'
    }

    It 'invokes the (mocked) license lookup once per dependency' {
        $null = New-ComplianceReport -ManifestPath $script:ManifestPath `
                                     -Policy $script:Policy -Database @{}
        Should -Invoke -ModuleName DependencyLicenseChecker Get-DependencyLicense -Times 3 -Exactly
    }

    It "reports PASS when no dependency is denied" {
        # Re-mock so nothing is denied.
        Mock -ModuleName DependencyLicenseChecker Get-DependencyLicense -MockWith { 'MIT' }
        $report = New-ComplianceReport -ManifestPath $script:ManifestPath `
                                       -Policy $script:Policy -Database @{}
        $report.Result          | Should -Be 'PASS'
        $report.Summary.Approved | Should -Be 3
        $report.Summary.Denied   | Should -Be 0
    }
}

Describe 'Format-ComplianceReport (text rendering)' {

    BeforeAll {
        $script:Report = [pscustomobject]@{
            Manifest = 'package.json'
            Entries  = @(
                [pscustomobject]@{ Name = 'express';     Version = '4.18.2'; License = 'MIT';     Status = 'approved' }
                [pscustomobject]@{ Name = 'gpl-tool';    Version = '1.0.0';  License = 'GPL-3.0'; Status = 'denied'   }
                [pscustomobject]@{ Name = 'mystery-lib'; Version = '0.0.1';  License = $null;     Status = 'unknown'  }
            )
            Summary  = [pscustomobject]@{ Approved = 1; Denied = 1; Unknown = 1; Total = 3 }
            Result   = 'FAIL'
        }
    }

    It 'renders one stable line per dependency plus a machine-parseable summary' {
        $text = Format-ComplianceReport -Report $script:Report
        $joined = $text -join "`n"

        $joined | Should -BeLike '*Manifest: package.json*'
        $joined | Should -BeLike '*express@4.18.2 | MIT | approved*'
        $joined | Should -BeLike '*gpl-tool@1.0.0 | GPL-3.0 | denied*'
        # A null license renders as the literal token UNKNOWN.
        $joined | Should -BeLike '*mystery-lib@0.0.1 | UNKNOWN | unknown*'
        $joined | Should -BeLike '*SUMMARY approved=1 denied=1 unknown=1 total=3*'
        $joined | Should -BeLike '*RESULT FAIL*'
    }
}

Describe 'bin/check-licenses.ps1 (CLI integration, real config)' {

    BeforeAll {
        $script:Cli = Join-Path $PSScriptRoot '..' 'bin' 'check-licenses.ps1'

        # Real (un-mocked) config + database files exercised end-to-end.
        $script:PolicyPath = Join-Path $TestDrive 'policy.json'
        Set-Content -Path $script:PolicyPath -Encoding utf8 -Value '{ "allow": ["MIT"], "deny": ["GPL-3.0"] }'

        $script:DbPath = Join-Path $TestDrive 'licenses.json'
        Set-Content -Path $script:DbPath -Encoding utf8 -Value '{ "express": "MIT", "gpl-tool": "GPL-3.0" }'

        $manifest = @'
{
  "name": "demo",
  "version": "1.0.0",
  "dependencies": { "express": "^4.18.2", "gpl-tool": "1.0.0", "mystery-lib": "0.0.1" }
}
'@
        $script:ManifestPath = Join-Path $TestDrive 'package.json'
        Set-Content -Path $script:ManifestPath -Value $manifest -Encoding utf8

        # Run the CLI as a child process so its `exit` does not kill the test
        # host. Stored as a script-scoped scriptblock so the It blocks can see it.
        $script:InvokeCli = {
            param([string[]] $CliArgs)
            $out = & pwsh -NoLogo -NoProfile -File $script:Cli @CliArgs 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
        }
    }

    It 'prints the full report and exits 0 in report mode' {
        $r = & $script:InvokeCli @('-ManifestPath', $script:ManifestPath,
                           '-PolicyPath', $script:PolicyPath,
                           '-LicenseDbPath', $script:DbPath)

        $r.ExitCode | Should -Be 0
        $r.Output   | Should -BeLike '*express@4.18.2 | MIT | approved*'
        $r.Output   | Should -BeLike '*gpl-tool@1.0.0 | GPL-3.0 | denied*'
        $r.Output   | Should -BeLike '*mystery-lib@0.0.1 | UNKNOWN | unknown*'
        $r.Output   | Should -BeLike '*SUMMARY approved=1 denied=1 unknown=1 total=3*'
        $r.Output   | Should -BeLike '*RESULT FAIL*'
    }

    It 'exits 1 under -FailOnViolation when a denied license is present' {
        $r = & $script:InvokeCli @('-ManifestPath', $script:ManifestPath,
                           '-PolicyPath', $script:PolicyPath,
                           '-LicenseDbPath', $script:DbPath, '-FailOnViolation')
        $r.ExitCode | Should -Be 1
    }

    It 'exits 2 with a meaningful error when the manifest is missing' {
        $r = & $script:InvokeCli @('-ManifestPath', (Join-Path $TestDrive 'ghost.json'),
                           '-PolicyPath', $script:PolicyPath,
                           '-LicenseDbPath', $script:DbPath)
        $r.ExitCode | Should -Be 2
        $r.Output   | Should -BeLike '*not found*'
    }
}
