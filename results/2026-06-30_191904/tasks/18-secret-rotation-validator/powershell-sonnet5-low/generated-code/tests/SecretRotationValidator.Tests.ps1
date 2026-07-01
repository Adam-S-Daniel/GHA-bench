<#
    Pester tests for the Secret Rotation Validator.
    TDD approach: tests are written before implementation and drive the
    module's public API (Get-SecretStatus, Get-RotationReport, Format-RotationReport).
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'SecretRotationValidator.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-SecretStatus' {

    It 'marks a secret as Expired when it is past its rotation policy' {
        $secret = [pscustomobject]@{
            Name              = 'db-password'
            LastRotated       = '2026-01-01'
            RotationPolicyDays = 30
            RequiredBy        = @('api-service')
        }
        $asOf = [datetime]'2026-03-01'

        $result = Get-SecretStatus -Secret $secret -WarningDays 7 -AsOf $asOf

        $result.Status | Should -Be 'Expired'
    }

    It 'marks a secret as Warning when inside the warning window but not yet expired' {
        $secret = [pscustomobject]@{
            Name              = 'api-key'
            LastRotated       = '2026-01-01'
            RotationPolicyDays = 30
            RequiredBy        = @('web-app')
        }
        # Policy expires 2026-01-31. AsOf 2026-01-26 => 5 days left, within 7-day window.
        $asOf = [datetime]'2026-01-26'

        $result = Get-SecretStatus -Secret $secret -WarningDays 7 -AsOf $asOf

        $result.Status | Should -Be 'Warning'
        $result.DaysRemaining | Should -Be 5
    }

    It 'marks a secret as Ok when well within its rotation policy' {
        $secret = [pscustomobject]@{
            Name              = 'tls-cert'
            LastRotated       = '2026-01-01'
            RotationPolicyDays = 90
            RequiredBy        = @('gateway')
        }
        $asOf = [datetime]'2026-01-10'

        $result = Get-SecretStatus -Secret $secret -WarningDays 7 -AsOf $asOf

        $result.Status | Should -Be 'Ok'
    }
}

Describe 'Get-RotationReport' {

    BeforeAll {
        $script:secrets = @(
            [pscustomobject]@{ Name = 'expired-secret'; LastRotated = '2026-01-01'; RotationPolicyDays = 30; RequiredBy = @('svc-a') }
            [pscustomobject]@{ Name = 'warning-secret'; LastRotated = '2026-01-01'; RotationPolicyDays = 60; RequiredBy = @('svc-b') }
            [pscustomobject]@{ Name = 'ok-secret';      LastRotated = '2026-01-01'; RotationPolicyDays = 365; RequiredBy = @('svc-c') }
        )
        $script:asOf = [datetime]'2026-02-25'
    }

    It 'throws a meaningful error when the config is null' {
        { Get-RotationReport -Secrets $null -WarningDays 7 -AsOf $script:asOf } | Should -Throw '*Secrets*'
    }

    It 'groups secrets into Expired, Warning, and Ok buckets' {
        $report = Get-RotationReport -Secrets $script:secrets -WarningDays 7 -AsOf $script:asOf

        $report.Expired.Name | Should -Be 'expired-secret'
        $report.Warning.Name | Should -Be 'warning-secret'
        $report.Ok.Name | Should -Be 'ok-secret'
    }

    It 'includes a summary count for each bucket' {
        $report = Get-RotationReport -Secrets $script:secrets -WarningDays 7 -AsOf $script:asOf

        $report.Summary.ExpiredCount | Should -Be 1
        $report.Summary.WarningCount | Should -Be 1
        $report.Summary.OkCount | Should -Be 1
        $report.Summary.TotalCount | Should -Be 3
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $script:secrets = @(
            [pscustomobject]@{ Name = 'expired-secret'; LastRotated = '2026-01-01'; RotationPolicyDays = 30; RequiredBy = @('svc-a') }
            [pscustomobject]@{ Name = 'ok-secret'; LastRotated = '2026-01-01'; RotationPolicyDays = 365; RequiredBy = @('svc-c') }
        )
        $script:report = Get-RotationReport -Secrets $script:secrets -WarningDays 7 -AsOf ([datetime]'2026-02-25')
    }

    It 'renders a markdown table containing each secret and its status' {
        $md = Format-RotationReport -Report $script:report -Format Markdown

        $md | Should -Match '\| *Name *\|'
        $md | Should -Match 'expired-secret'
        $md | Should -Match 'Expired'
        $md | Should -Match 'ok-secret'
        $md | Should -Match 'Ok'
    }

    It 'renders valid JSON containing the summary and secrets' {
        $json = Format-RotationReport -Report $script:report -Format Json
        $parsed = $json | ConvertFrom-Json

        $parsed.Summary.TotalCount | Should -Be 2
        $parsed.Expired.Name | Should -Be 'expired-secret'
    }

    It 'throws a meaningful error for an unsupported format' {
        { Format-RotationReport -Report $script:report -Format 'Xml' } | Should -Throw
    }
}

Describe 'Import-SecretConfig' {

    It 'loads secrets from a JSON config file' {
        $path = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.sample.json'

        $secrets = Import-SecretConfig -Path $path

        $secrets.Count | Should -Be 3
        $secrets[0].Name | Should -Be 'db-password'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path './fixtures/does-not-exist.json' } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the file contains invalid JSON' {
        $badPath = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $badPath -Value '{ not valid json'

        { Import-SecretConfig -Path $badPath } | Should -Throw '*Failed to parse*'
    }
}
