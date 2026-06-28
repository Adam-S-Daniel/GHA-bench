#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester unit tests for the Secret Rotation Validator (red/green TDD).

.DESCRIPTION
    These tests drive the design of SecretRotationValidator.psm1. They are pure
    logic tests with deterministic inputs (a fixed reference date) so they never
    depend on the wall-clock. The same fixtures used here under fixtures/ are the
    fixtures the act-based CI integration harness feeds through the workflow, so
    the unit expectations and the pipeline expectations stay in lock-step.
#>

BeforeAll {
    # Resolve paths relative to this test file so the suite runs from any CWD
    # (locally, in CI, or inside the act container).
    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $RepoRoot 'SecretRotationValidator.psm1'
    $script:FixtureDir = Join-Path $RepoRoot 'fixtures'

    Import-Module $ModulePath -Force

    # A single fixed "today" keeps every expectation deterministic.
    $script:RefDate = '2026-06-28'
}

Describe 'Get-SecretRotationStatus' {

    It 'classifies a secret rotated well beyond its policy as Expired' {
        $secret = [pscustomobject]@{
            name              = 'db-password'
            lastRotated       = '2026-01-01'
            rotationPolicyDays = 90
            requiredBy        = @('api', 'worker')
        }

        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14

        $result.Name              | Should -Be 'db-password'
        $result.DaysSinceRotation | Should -Be 178
        $result.DaysUntilExpiry   | Should -Be -88
        $result.Status            | Should -Be 'Expired'
        ($result.RequiredBy -join ',') | Should -Be 'api,worker'
    }

    It 'classifies a secret inside the warning window as Warning' {
        $secret = [pscustomobject]@{
            name              = 'api-token'
            lastRotated       = '2026-04-01'
            rotationPolicyDays = 90
            requiredBy        = @('gateway')
        }

        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14

        $result.DaysUntilExpiry | Should -Be 2
        $result.Status          | Should -Be 'Warning'
    }

    It 'classifies a secret far from expiry as Ok' {
        $secret = [pscustomobject]@{
            name              = 'tls-cert'
            lastRotated       = '2026-06-01'
            rotationPolicyDays = 365
            requiredBy        = @('web')
        }

        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14

        $result.DaysUntilExpiry | Should -Be 338
        $result.Status          | Should -Be 'Ok'
    }

    It 'treats a secret due exactly today (0 days left) as Expired (boundary)' {
        $secret = [pscustomobject]@{
            name              = 'edge-zero'
            lastRotated       = '2026-03-30'  # exactly 90 days before the ref date
            rotationPolicyDays = 90
            requiredBy        = @('svc')
        }

        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14

        $result.DaysUntilExpiry | Should -Be 0
        $result.Status          | Should -Be 'Expired'
    }

    It 'treats a secret exactly at the warning-window edge as Warning (boundary)' {
        # daysUntilExpiry == WarningDays must still be Warning, not Ok.
        $secret = [pscustomobject]@{
            name              = 'edge-warn'
            lastRotated       = '2026-04-14'  # 75 days old, policy 89 -> 14 days left
            rotationPolicyDays = 89
            requiredBy        = @('svc')
        }

        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14

        $result.DaysUntilExpiry | Should -Be 14
        $result.Status          | Should -Be 'Warning'
    }

    It 'throws a meaningful error when lastRotated is not a valid date' {
        $secret = [pscustomobject]@{
            name              = 'bad-date'
            lastRotated       = 'not-a-date'
            rotationPolicyDays = 90
            requiredBy        = @('svc')
        }

        { Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14 } |
            Should -Throw -ExpectedMessage "*bad-date*lastRotated*"
    }

    It 'throws when rotationPolicyDays is not a positive integer' {
        $secret = [pscustomobject]@{
            name              = 'bad-policy'
            lastRotated       = '2026-01-01'
            rotationPolicyDays = 0
            requiredBy        = @('svc')
        }

        { Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningDays 14 } |
            Should -Throw -ExpectedMessage "*bad-policy*rotationPolicyDays*"
    }
}

Describe 'Import-SecretConfig' {

    It 'loads a valid configuration file and exposes referenceDate, warningDays and secrets' {
        $config = Import-SecretConfig -Path (Join-Path $FixtureDir 'case1-mixed.json')

        $config.ReferenceDate    | Should -Be '2026-06-28'
        $config.WarningDays      | Should -Be 14
        $config.Secrets.Count    | Should -Be 3
        $config.Secrets[0].name  | Should -Be 'db-password'
    }

    It 'throws a clear error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $FixtureDir 'does-not-exist.json') } |
            Should -Throw -ExpectedMessage "*not found*"
    }

    It 'throws a clear error when the file contains invalid JSON' {
        $bad = Join-Path $TestDrive 'invalid.json'
        Set-Content -LiteralPath $bad -Value '{ this is : not json' -Encoding utf8
        { Import-SecretConfig -Path $bad } | Should -Throw -ExpectedMessage "*Failed to parse JSON*"
    }

    It 'throws when the secrets array is missing' {
        $noSecrets = Join-Path $TestDrive 'no-secrets.json'
        Set-Content -LiteralPath $noSecrets -Value '{ "warningDays": 14 }' -Encoding utf8
        { Import-SecretConfig -Path $noSecrets } | Should -Throw -ExpectedMessage "*must contain a 'secrets' array*"
    }

    It 'throws when the secrets array is empty' {
        $empty = Join-Path $TestDrive 'empty-secrets.json'
        Set-Content -LiteralPath $empty -Value '{ "secrets": [] }' -Encoding utf8
        { Import-SecretConfig -Path $empty } | Should -Throw -ExpectedMessage "*no secrets*"
    }
}

Describe 'Get-SecretRotationReport' {

    BeforeAll {
        $script:Case1 = Import-SecretConfig -Path (Join-Path $FixtureDir 'case1-mixed.json')
        $script:Case3 = Import-SecretConfig -Path (Join-Path $FixtureDir 'case3-mostly-expired.json')
    }

    It 'computes a correct summary across all urgency levels' {
        $report = Get-SecretRotationReport -Secrets $Case1.Secrets -ReferenceDate $RefDate -WarningDays 14

        $report.Summary.Expired | Should -Be 1
        $report.Summary.Warning | Should -Be 1
        $report.Summary.Ok      | Should -Be 1
        $report.Summary.Total   | Should -Be 3
    }

    It 'groups secrets by urgency' {
        $report = Get-SecretRotationReport -Secrets $Case1.Secrets -ReferenceDate $RefDate -WarningDays 14

        $report.Groups.Expired.Name | Should -Be 'db-password'
        $report.Groups.Warning.Name | Should -Be 'api-token'
        $report.Groups.Ok.Name      | Should -Be 'tls-cert'
    }

    It 'sorts within a group by most-overdue first' {
        # case3 has two expired secrets: legacy-key (-453) and ssh-deploy-key (-28).
        $report = Get-SecretRotationReport -Secrets $Case3.Secrets -ReferenceDate $RefDate -WarningDays 30

        $report.Summary.Expired      | Should -Be 2
        $report.Groups.Expired[0].Name | Should -Be 'legacy-key'      # -453, most overdue
        $report.Groups.Expired[1].Name | Should -Be 'ssh-deploy-key'  # -28
    }
}

Describe 'Format-SecretRotationReport' {

    BeforeAll {
        $script:Case1   = Import-SecretConfig -Path (Join-Path $FixtureDir 'case1-mixed.json')
        $script:Case3   = Import-SecretConfig -Path (Join-Path $FixtureDir 'case3-mostly-expired.json')
        $script:Report1 = Get-SecretRotationReport -Secrets $Case1.Secrets -ReferenceDate $RefDate -WarningDays 14
        $script:Report3 = Get-SecretRotationReport -Secrets $Case3.Secrets -ReferenceDate $RefDate -WarningDays 30
    }

    It 'renders the exact Summary lines (machine-readable contract)' {
        $expected = @(
            'ROTATION-SUMMARY expired=1 warning=1 ok=1 total=3'
            'SECRET name=db-password status=Expired daysSinceRotation=178 daysUntilExpiry=-88 requiredBy=api,worker'
            'SECRET name=api-token status=Warning daysSinceRotation=88 daysUntilExpiry=2 requiredBy=gateway'
            'SECRET name=tls-cert status=Ok daysSinceRotation=27 daysUntilExpiry=338 requiredBy=web'
        ) -join [Environment]::NewLine

        Format-SecretRotationReport -Report $Report1 -Format Summary | Should -Be $expected
    }

    It 'renders a Markdown report with header bullets and a data row' {
        $md = Format-SecretRotationReport -Report $Report1 -Format Markdown

        $md | Should -Match '# Secret Rotation Report'
        $md | Should -Match '\- \*\*Expired:\*\* 1'
        $md | Should -BeLike '*| db-password | 2026-01-01 | 90 | -88 | api, worker |*'
    }

    It 'renders _None_ for an empty urgency group in Markdown' {
        # case3 has no Warning secrets.
        $md = Format-SecretRotationReport -Report $Report3 -Format Markdown
        $md | Should -Match '## Warning \(0\)'
        $md | Should -Match '_None_'
    }

    It 'renders valid JSON that round-trips to the same data' {
        $json = Format-SecretRotationReport -Report $Report1 -Format Json
        $parsed = $json | ConvertFrom-Json

        $parsed.referenceDate            | Should -Be '2026-06-28'
        $parsed.warningDays              | Should -Be 14
        $parsed.summary.expired          | Should -Be 1
        $parsed.summary.total            | Should -Be 3
        $parsed.groups.expired[0].name   | Should -Be 'db-password'
        $parsed.groups.expired[0].daysUntilExpiry | Should -Be -88
        $parsed.groups.expired[0].status | Should -Be 'Expired'
    }
}

Describe 'Invoke-SecretRotationValidator (end-to-end)' {

    It 'produces the exact Summary output for the mixed fixture' {
        $expected = @(
            'ROTATION-SUMMARY expired=1 warning=1 ok=1 total=3'
            'SECRET name=db-password status=Expired daysSinceRotation=178 daysUntilExpiry=-88 requiredBy=api,worker'
            'SECRET name=api-token status=Warning daysSinceRotation=88 daysUntilExpiry=2 requiredBy=gateway'
            'SECRET name=tls-cert status=Ok daysSinceRotation=27 daysUntilExpiry=338 requiredBy=web'
        ) -join [Environment]::NewLine

        $out = Invoke-SecretRotationValidator -ConfigPath (Join-Path $FixtureDir 'case1-mixed.json') -Format Summary
        $out | Should -Be $expected
    }

    It 'honours an explicit -WarningDays override (param beats config)' {
        # Widening the window to 400 days pulls tls-cert (338 left) into Warning.
        $out = Invoke-SecretRotationValidator -ConfigPath (Join-Path $FixtureDir 'case1-mixed.json') `
            -Format Summary -WarningDays 400
        $out | Should -Match 'ROTATION-SUMMARY expired=1 warning=2 ok=0 total=3'
        $out | Should -Match 'SECRET name=tls-cert status=Warning'
    }

    It 'honours an explicit -ReferenceDate override (param beats config)' {
        # Moving "today" forward to 2026-08-01 expires signing-key in the all-ok fixture.
        $out = Invoke-SecretRotationValidator -ConfigPath (Join-Path $FixtureDir 'case2-all-ok.json') `
            -Format Summary -ReferenceDate '2026-08-01'
        $out | Should -Match 'ROTATION-SUMMARY expired=1 warning=0 ok=1 total=2'
        $out | Should -Match 'SECRET name=signing-key status=Expired'
    }

    It 'throws a meaningful error for a missing config file' {
        { Invoke-SecretRotationValidator -ConfigPath (Join-Path $FixtureDir 'nope.json') -Format Summary } |
            Should -Throw -ExpectedMessage "*not found*"
    }
}
