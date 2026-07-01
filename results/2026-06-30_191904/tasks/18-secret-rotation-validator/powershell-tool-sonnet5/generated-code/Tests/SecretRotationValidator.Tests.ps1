#Requires -Modules Pester

# Unit tests for the SecretRotationValidator module. Written TDD-style: each
# Describe block below started as a failing test before the corresponding
# function existed in ../SecretRotationValidator.psm1.

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'SecretRotationValidator.psm1'
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Import-SecretConfig' {

    Context 'valid configuration' {
        It 'loads all secrets from a valid config file' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
            $config.Secrets.Count | Should -Be 6
        }

        It 'parses LastRotated as a [datetime]' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
            $secret = $config.Secrets | Where-Object Name -eq 'db-password'
            $secret.LastRotated | Should -BeOfType [datetime]
            $secret.LastRotated | Should -Be ([datetime]'2025-10-01')
        }

        It 'parses RotationPolicyDays as an int' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
            $secret = $config.Secrets | Where-Object Name -eq 'db-password'
            $secret.RotationPolicyDays | Should -Be 90
        }

        It 'parses RequiredBy as a string array' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
            $secret = $config.Secrets | Where-Object Name -eq 'db-password'
            $secret.RequiredBy | Should -Be @('payments-api', 'checkout-service')
        }

        It 'reads the top-level WarningWindowDays default' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
            $config.WarningWindowDays | Should -Be 14
        }

        It 'accepts an empty secrets array' {
            $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'empty-secrets.json')
            $config.Secrets.Count | Should -Be 0
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the file does not exist' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'does-not-exist.json') } |
                Should -Throw '*not found*'
        }

        It 'throws a meaningful error on malformed JSON' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'malformed.json') } |
                Should -Throw '*JSON*'
        }

        It 'throws a meaningful error when the secrets key is missing' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'missing-secrets-key.json') } |
                Should -Throw '*secrets*'
        }

        It 'throws a meaningful error when a secret is missing its name' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'missing-name.json') } |
                Should -Throw '*name*'
        }

        It 'throws a meaningful error when lastRotated is not a valid date' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'bad-date.json') } |
                Should -Throw '*date*'
        }

        It 'throws a meaningful error when rotationPolicyDays is not positive' {
            { Import-SecretConfig -Path (Join-Path $FixturesPath 'bad-policy.json') } |
                Should -Throw '*rotationPolicyDays*'
        }
    }
}

Describe 'Get-SecretStatus' {

    BeforeAll {
        $AsOf = [datetime]'2026-01-15'

        function New-TestSecret {
            param($Name, $LastRotated, $RotationPolicyDays, $RequiredBy = @('some-service'))
            [PSCustomObject]@{
                Name               = $Name
                LastRotated        = [datetime]$LastRotated
                RotationPolicyDays = $RotationPolicyDays
                RequiredBy         = $RequiredBy
            }
        }
    }

    It 'computes the correct ExpiryDate' {
        $secret = New-TestSecret 'db-password' '2025-10-01' 90
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.ExpiryDate | Should -Be ([datetime]'2025-12-30')
    }

    It 'marks a secret already past its expiry date as Expired' {
        $secret = New-TestSecret 'db-password' '2025-10-01' 90
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.DaysUntilExpiry | Should -Be -16
        $result.Status | Should -Be 'Expired'
    }

    It 'marks a secret expiring within the warning window as Warning' {
        $secret = New-TestSecret 'api-key-stripe' '2026-01-01' 20
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.DaysUntilExpiry | Should -Be 6
        $result.Status | Should -Be 'Warning'
    }

    It 'marks a secret expiring well outside the warning window as Ok' {
        $secret = New-TestSecret 'github-token' '2026-01-10' 365
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.DaysUntilExpiry | Should -Be 360
        $result.Status | Should -Be 'Ok'
    }

    It 'treats a secret expiring exactly at the warning window boundary as Warning (inclusive)' {
        $secret = New-TestSecret 'slack-webhook' '2025-10-21' 100
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.DaysUntilExpiry | Should -Be 14
        $result.Status | Should -Be 'Warning'
    }

    It 'treats a secret expiring today (0 days) as Warning, not Expired' {
        $secret = New-TestSecret 'expires-today' '2025-11-26' 50
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.DaysUntilExpiry | Should -Be 0
        $result.Status | Should -Be 'Warning'
    }

    It 'preserves the RequiredBy list on the result' {
        $secret = New-TestSecret 'db-password' '2025-10-01' 90 -RequiredBy @('payments-api', 'checkout-service')
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14 -AsOf $AsOf
        $result.RequiredBy | Should -Be @('payments-api', 'checkout-service')
    }

    It 'defaults AsOf to the current date when not supplied' {
        $secret = New-TestSecret 'github-token' (Get-Date).ToString('yyyy-MM-dd') 365
        $result = Get-SecretStatus -Secret $secret -WarningWindowDays 14
        $result.Status | Should -Be 'Ok'
    }
}

Describe 'New-SecretRotationReport' {

    BeforeAll {
        $AsOf = [datetime]'2026-01-15'
        $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
        $script:report = New-SecretRotationReport -Secrets $config.Secrets -WarningWindowDays $config.WarningWindowDays -AsOf $AsOf
    }

    It 'groups secrets into Expired, Warning, and Ok buckets' {
        $report.Expired.Count | Should -Be 2
        $report.Warning.Count | Should -Be 3
        $report.Ok.Count | Should -Be 1
    }

    It 'puts the correct secrets in the Expired bucket' {
        ($report.Expired.Name | Sort-Object) | Should -Be @('db-password', 'tls-cert')
    }

    It 'puts the correct secrets in the Warning bucket' {
        ($report.Warning.Name | Sort-Object) | Should -Be @('api-key-stripe', 'expires-today', 'slack-webhook')
    }

    It 'puts the correct secrets in the Ok bucket' {
        $report.Ok.Name | Should -Be @('github-token')
    }

    It 'sorts each bucket by DaysUntilExpiry ascending (most urgent first)' {
        $report.Expired.Name | Should -Be @('db-password', 'tls-cert')
    }

    It 'includes a summary with correct counts' {
        $report.Summary.Total | Should -Be 6
        $report.Summary.ExpiredCount | Should -Be 2
        $report.Summary.WarningCount | Should -Be 3
        $report.Summary.OkCount | Should -Be 1
    }

    It 'records the WarningWindowDays and AsOf used to generate the report' {
        $report.WarningWindowDays | Should -Be 14
        $report.AsOf | Should -Be $AsOf
    }

    It 'produces an empty report with zero counts when there are no secrets' {
        $emptyReport = New-SecretRotationReport -Secrets @() -WarningWindowDays 14 -AsOf $AsOf
        $emptyReport.Summary.Total | Should -Be 0
        $emptyReport.Expired.Count | Should -Be 0
        $emptyReport.Warning.Count | Should -Be 0
        $emptyReport.Ok.Count | Should -Be 0
    }
}

Describe 'Format-SecretRotationReport' {

    BeforeAll {
        $AsOf = [datetime]'2026-01-15'
        $config = Import-SecretConfig -Path (Join-Path $FixturesPath 'mixed-secrets.json')
        $script:report = New-SecretRotationReport -Secrets $config.Secrets -WarningWindowDays $config.WarningWindowDays -AsOf $AsOf
    }

    Context 'Markdown format' {
        BeforeAll {
            $script:markdown = Format-SecretRotationReport -Report $report -Format Markdown
        }

        It 'includes a report title' {
            $markdown | Should -Match '# Secret Rotation Report'
        }

        It 'includes an EXPIRED section header' {
            $markdown | Should -Match '## Expired'
        }

        It 'includes a WARNING section header' {
            $markdown | Should -Match '## Warning'
        }

        It 'includes an OK section header' {
            $markdown | Should -Match '## Ok'
        }

        It 'lists every expired secret name in the Expired section' {
            $markdown | Should -Match 'db-password'
            $markdown | Should -Match 'tls-cert'
        }

        It 'renders RequiredBy services joined by comma' {
            $markdown | Should -Match 'payments-api, checkout-service'
        }

        It 'includes the summary counts' {
            $markdown | Should -Match 'Expired: 2'
            $markdown | Should -Match 'Warning: 3'
            $markdown | Should -Match 'Ok: 1'
        }
    }

    Context 'JSON format' {
        BeforeAll {
            $script:jsonText = Format-SecretRotationReport -Report $report -Format Json
        }

        It 'produces valid, parseable JSON' {
            { $script:jsonText | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        }

        It 'round-trips the summary counts' {
            $parsed = $jsonText | ConvertFrom-Json
            $parsed.Summary.ExpiredCount | Should -Be 2
            $parsed.Summary.WarningCount | Should -Be 3
            $parsed.Summary.OkCount | Should -Be 1
        }

        It 'round-trips the expired secret names' {
            $parsed = $jsonText | ConvertFrom-Json
            ($parsed.Expired.Name | Sort-Object) | Should -Be @('db-password', 'tls-cert')
        }
    }

    It 'throws a meaningful error for an unsupported format' {
        { Format-SecretRotationReport -Report $report -Format 'Xml' } | Should -Throw
    }
}
