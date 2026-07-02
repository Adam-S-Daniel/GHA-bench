#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester test suite for the Secret Rotation Validator module.
# Written TDD-style: each Describe/It block below was authored to fail first,
# then the minimum implementation was added to SecretRotationValidator.psm1
# to make it pass.

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SecretRotationValidator.psm1'
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'Get-SecretRotationStatus' {

    Context 'when the rotation due date is in the past' {
        It 'marks the secret as Expired' {
            $secret = [PSCustomObject]@{
                Name               = 'db-password'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 30
                RequiredBy         = @('billing-service')
            }
            $now = Get-Date '2026-03-01'

            $result = Get-SecretRotationStatus -Secret $secret -WarningDays 7 -Now $now

            $result.Status | Should -Be 'Expired'
        }
    }

    Context 'when the due date falls inside the warning window' {
        It 'marks the secret as Warning' {
            # LastRotated 2026-01-01 + 30 days = due 2026-01-31. "Now" is
            # 2026-01-27 -> 4 days until due, inside a 7-day warning window.
            $secret = [PSCustomObject]@{
                Name               = 'api-key'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 30
                RequiredBy         = @('checkout-service')
            }
            $now = Get-Date '2026-01-27'

            $result = Get-SecretRotationStatus -Secret $secret -WarningDays 7 -Now $now

            $result.Status | Should -Be 'Warning'
            $result.DaysUntilDue | Should -Be 4
        }

        It 'treats the due date exactly WarningDays away as Warning (inclusive boundary)' {
            $secret = [PSCustomObject]@{
                Name               = 'tls-cert'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 30
                RequiredBy         = @('edge-proxy')
            }
            $now = Get-Date '2026-01-24' # due 2026-01-31 -> exactly 7 days away

            $result = Get-SecretRotationStatus -Secret $secret -WarningDays 7 -Now $now

            $result.Status | Should -Be 'Warning'
        }
    }

    Context 'when the due date is well beyond the warning window' {
        It 'marks the secret as Ok' {
            $secret = [PSCustomObject]@{
                Name               = 'ssh-key'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 90
                RequiredBy         = @('deploy-bot')
            }
            $now = Get-Date '2026-01-05'

            $result = Get-SecretRotationStatus -Secret $secret -WarningDays 7 -Now $now

            $result.Status | Should -Be 'Ok'
        }
    }

    Context 'result shape' {
        It 'passes through Name, RotationPolicyDays and RequiredBy unchanged' {
            $secret = [PSCustomObject]@{
                Name               = 'stripe-webhook-secret'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 60
                RequiredBy         = @('billing-service', 'webhook-gateway')
            }
            $now = Get-Date '2026-01-05'

            $result = Get-SecretRotationStatus -Secret $secret -WarningDays 7 -Now $now

            $result.Name | Should -Be 'stripe-webhook-secret'
            $result.RotationPolicyDays | Should -Be 60
            $result.RequiredBy | Should -Be @('billing-service', 'webhook-gateway')
            $result.DueDate | Should -Be (Get-Date '2026-03-02')
        }
    }
}

Describe 'Import-SecretConfig' {

    Context 'with a valid configuration file' {
        It 'loads every secret with the expected fields' {
            $path = Join-Path $FixturesPath 'valid-secrets.json'

            $secrets = Import-SecretConfig -Path $path

            $secrets.Count | Should -Be 2
            $secrets[0].Name | Should -Be 'db-password'
            $secrets[0].RotationPolicyDays | Should -Be 30
            $secrets[0].RequiredBy | Should -Be @('billing-service', 'reporting-service')
        }
    }

    Context 'when the file does not exist' {
        It 'throws a clear, actionable error' {
            $missingPath = Join-Path $FixturesPath 'does-not-exist.json'

            { Import-SecretConfig -Path $missingPath } |
                Should -Throw '*Secret configuration file not found*'
        }
    }

    Context 'when the file is not valid JSON' {
        It 'throws a clear parsing error' {
            $badPath = Join-Path $TestDrive 'bad.json'
            Set-Content -Path $badPath -Value '{ this is not json ]'

            { Import-SecretConfig -Path $badPath } |
                Should -Throw '*not valid JSON*'
        }
    }

    Context 'when a secret entry is missing a required field' {
        It 'throws an error naming the offending secret and field' {
            $incompletePath = Join-Path $TestDrive 'incomplete.json'
            Set-Content -Path $incompletePath -Value '[{ "Name": "no-policy-secret", "LastRotated": "2026-01-01" }]'

            { Import-SecretConfig -Path $incompletePath } |
                Should -Throw '*no-policy-secret*RotationPolicyDays*'
        }
    }
}

Describe 'New-RotationReport' {

    BeforeAll {
        $secrets = @(
            [PSCustomObject]@{ Name = 'db-password'; LastRotated = '2026-01-01'; RotationPolicyDays = 30; RequiredBy = @('billing-service') }   # due 2026-01-31 -> Expired
            [PSCustomObject]@{ Name = 'api-key'; LastRotated = '2026-01-01'; RotationPolicyDays = 90; RequiredBy = @('checkout-service') }        # due 2026-04-01 -> Warning
            [PSCustomObject]@{ Name = 'ssh-key'; LastRotated = '2026-03-01'; RotationPolicyDays = 180; RequiredBy = @('deploy-bot') }             # due 2026-08-28 -> Ok
        )
        $now = Get-Date '2026-03-28'
    }

    It 'groups secrets into Expired, Warning and Ok buckets' {
        $report = New-RotationReport -Secrets $secrets -WarningDays 7 -Now $now

        $report.Expired.Name | Should -Be @('db-password')
        $report.Warning.Name | Should -Be @('api-key')
        $report.Ok.Name | Should -Be @('ssh-key')
    }

    It 'computes accurate summary counts' {
        $report = New-RotationReport -Secrets $secrets -WarningDays 7 -Now $now

        $report.Summary.Total | Should -Be 3
        $report.Summary.ExpiredCount | Should -Be 1
        $report.Summary.WarningCount | Should -Be 1
        $report.Summary.OkCount | Should -Be 1
    }

    It 'records the WarningDays and generation timestamp used' {
        $report = New-RotationReport -Secrets $secrets -WarningDays 7 -Now $now

        $report.WarningDays | Should -Be 7
        $report.GeneratedAt | Should -Be $now
    }

    It 'handles an empty secret list without error' {
        $report = New-RotationReport -Secrets @() -WarningDays 7 -Now $now

        $report.Summary.Total | Should -Be 0
        $report.Expired | Should -BeNullOrEmpty
        $report.Warning | Should -BeNullOrEmpty
        $report.Ok | Should -BeNullOrEmpty
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $secrets = @(
            [PSCustomObject]@{ Name = 'db-password'; LastRotated = '2026-01-01'; RotationPolicyDays = 30; RequiredBy = @('billing-service') }
            [PSCustomObject]@{ Name = 'api-key'; LastRotated = '2026-01-01'; RotationPolicyDays = 90; RequiredBy = @('checkout-service') }
            [PSCustomObject]@{ Name = 'ssh-key'; LastRotated = '2026-03-01'; RotationPolicyDays = 180; RequiredBy = @('deploy-bot') }
        )
        $now = Get-Date '2026-03-28'
        $report = New-RotationReport -Secrets $secrets -WarningDays 7 -Now $now
    }

    Context 'Markdown format' {
        It 'renders a heading, summary counts and a table row per secret' {
            $markdown = Format-RotationReport -Report $report -Format Markdown

            $markdown | Should -Match '# Secret Rotation Report'
            $markdown | Should -Match 'Expired:\s*1'
            $markdown | Should -Match 'Warning:\s*1'
            $markdown | Should -Match 'Ok:\s*1'
            $markdown | Should -Match '\| *db-password *\|'
            $markdown | Should -Match '\| *api-key *\|'
            $markdown | Should -Match '\| *ssh-key *\|'
        }
    }

    Context 'Json format' {
        It 'renders valid JSON round-tripping the summary and secret names' {
            $json = Format-RotationReport -Report $report -Format Json

            { $json | ConvertFrom-Json } | Should -Not -Throw
            $parsed = $json | ConvertFrom-Json

            $parsed.Summary.Total | Should -Be 3
            $parsed.Expired[0].Name | Should -Be 'db-password'
            $parsed.Warning[0].Name | Should -Be 'api-key'
            $parsed.Ok[0].Name | Should -Be 'ssh-key'
        }
    }

    Context 'an unsupported format' {
        It 'throws a clear error' {
            { Format-RotationReport -Report $report -Format 'Xml' } | Should -Throw
        }
    }
}

Describe 'Invoke-SecretRotationCheck' {

    BeforeAll {
        $now = Get-Date '2026-03-28'
        $mixedConfigPath = Join-Path $TestDrive 'mixed-secrets.json'
        @(
            [PSCustomObject]@{ Name = 'db-password'; LastRotated = '2026-01-01'; RotationPolicyDays = 30; RequiredBy = @('billing-service') }
            [PSCustomObject]@{ Name = 'api-key'; LastRotated = '2026-01-01'; RotationPolicyDays = 90; RequiredBy = @('checkout-service') }
            [PSCustomObject]@{ Name = 'ssh-key'; LastRotated = '2026-03-01'; RotationPolicyDays = 180; RequiredBy = @('deploy-bot') }
        ) | ConvertTo-Json | Set-Content -Path $mixedConfigPath

        $healthyConfigPath = Join-Path $TestDrive 'healthy-secrets.json'
        @(
            [PSCustomObject]@{ Name = 'ssh-key'; LastRotated = '2026-03-01'; RotationPolicyDays = 180; RequiredBy = @('deploy-bot') }
        ) | ConvertTo-Json | Set-Content -Path $healthyConfigPath
    }

    It 'wires Import-SecretConfig, New-RotationReport and Format-RotationReport together' {
        $result = Invoke-SecretRotationCheck -ConfigPath $mixedConfigPath -WarningDays 7 -OutputFormat Json -Now $now

        $parsed = $result | ConvertFrom-Json
        $parsed.Summary.ExpiredCount | Should -Be 1
        $parsed.Summary.WarningCount | Should -Be 1
        $parsed.Summary.OkCount | Should -Be 1
    }

    It 'defaults OutputFormat to Markdown' {
        $result = Invoke-SecretRotationCheck -ConfigPath $mixedConfigPath -WarningDays 7 -Now $now

        $result | Should -Match '# Secret Rotation Report'
    }

    It 'propagates a meaningful error when the config file is missing' {
        $missingPath = Join-Path $TestDrive 'missing.json'

        { Invoke-SecretRotationCheck -ConfigPath $missingPath -WarningDays 7 -Now $now } |
            Should -Throw '*Secret configuration file not found*'
    }

    Context 'with -FailOnExpired' {
        It 'throws when expired secrets are present' {
            { Invoke-SecretRotationCheck -ConfigPath $mixedConfigPath -WarningDays 7 -Now $now -FailOnExpired } |
                Should -Throw '*1 secret(s) have expired*'
        }

        It 'does not throw when no secrets are expired' {
            { Invoke-SecretRotationCheck -ConfigPath $healthyConfigPath -WarningDays 7 -Now $now -FailOnExpired } |
                Should -Not -Throw
        }
    }
}
