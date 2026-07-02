# Pester tests for the Secret Rotation Validator.
# TDD: each Describe block below was written before its corresponding
# implementation in src/SecretRotationValidator.psm1.

BeforeAll {
    Import-Module "$PSScriptRoot/../src/SecretRotationValidator.psm1" -Force
}

Describe 'Get-SecretRotationStatus' {
    It 'marks a secret as Expired when days since rotation exceeds the policy' {
        $secret = [pscustomobject]@{
            Name           = 'db-password'
            LastRotated    = '2026-01-01'
            RotationDays   = 30
            RequiredBy     = @('api-service')
        }
        $result = Get-SecretRotationStatus -Secret $secret -CurrentDate ([datetime]'2026-03-01') -WarningDays 7

        $result.Status | Should -Be 'Expired'
    }

    It 'marks a secret as Warning when it falls due within the warning window' {
        $secret = [pscustomobject]@{
            Name         = 'api-key'
            LastRotated  = '2026-01-01'
            RotationDays = 30
            RequiredBy   = @('billing-service')
        }
        # policy expires 2026-01-31; warning window is 7 days; "today" is 2026-01-26 -> 5 days left
        $result = Get-SecretRotationStatus -Secret $secret -CurrentDate ([datetime]'2026-01-26') -WarningDays 7

        $result.Status | Should -Be 'Warning'
        $result.DaysRemaining | Should -Be 5
    }

    It 'marks a secret as Ok when it is well within its rotation policy' {
        $secret = [pscustomobject]@{
            Name         = 'tls-cert'
            LastRotated  = '2026-01-01'
            RotationDays = 90
            RequiredBy   = @('edge-proxy')
        }
        $result = Get-SecretRotationStatus -Secret $secret -CurrentDate ([datetime]'2026-01-15') -WarningDays 7

        $result.Status | Should -Be 'Ok'
    }
}

Describe 'Import-SecretConfig' {
    It 'loads secrets from a JSON configuration file' {
        $configPath = "$PSScriptRoot/../fixtures/sample-secrets.json"
        $secrets = Import-SecretConfig -Path $configPath

        $secrets.Count | Should -Be 4
        $secrets[0].Name | Should -Be 'db-password'
    }

    It 'throws a meaningful error when the config file does not exist' {
        { Import-SecretConfig -Path "$PSScriptRoot/../fixtures/does-not-exist.json" } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the config file is not valid JSON' {
        $badPath = "$PSScriptRoot/../fixtures/bad-secrets.json"
        { Import-SecretConfig -Path $badPath } | Should -Throw '*invalid JSON*'
    }
}

Describe 'New-RotationReport' {
    It 'groups evaluated secrets into Expired, Warning, and Ok buckets' {
        $configPath = "$PSScriptRoot/../fixtures/sample-secrets.json"
        $secrets = Import-SecretConfig -Path $configPath
        $report = New-RotationReport -Secrets $secrets -CurrentDate ([datetime]'2026-03-01') -WarningDays 7

        $report.Expired.Count | Should -Be 1
        $report.Warning.Count | Should -Be 1
        $report.Ok.Count | Should -Be 2
        $report.GeneratedAt | Should -Not -BeNullOrEmpty
    }
}

Describe 'Format-RotationReport' {
    BeforeAll {
        $configPath = "$PSScriptRoot/../fixtures/sample-secrets.json"
        $secrets = Import-SecretConfig -Path $configPath
        $script:report = New-RotationReport -Secrets $secrets -CurrentDate ([datetime]'2026-03-01') -WarningDays 7
    }

    It 'formats the report as a markdown table with urgency sections' {
        $markdown = Format-RotationReport -Report $script:report -Format Markdown

        $markdown | Should -Match '## Expired'
        $markdown | Should -Match '## Warning'
        $markdown | Should -Match '## Ok'
        $markdown | Should -Match '\| Name \|'
    }

    It 'formats the report as valid JSON' {
        $json = Format-RotationReport -Report $script:report -Format Json
        { $json | ConvertFrom-Json } | Should -Not -Throw

        $parsed = $json | ConvertFrom-Json
        $parsed.Expired.Count | Should -Be 1
    }
}

Describe 'Invoke-SecretRotationValidator (end to end)' {
    It 'produces a markdown report and exits successfully for a valid config' {
        $configPath = "$PSScriptRoot/../fixtures/sample-secrets.json"
        $result = Invoke-SecretRotationValidator -ConfigPath $configPath -WarningDays 7 -OutputFormat Markdown -CurrentDate ([datetime]'2026-03-01')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '## Expired'
    }

    It 'returns a non-zero exit code when expired secrets are found and FailOnExpired is set' {
        $configPath = "$PSScriptRoot/../fixtures/sample-secrets.json"
        $result = Invoke-SecretRotationValidator -ConfigPath $configPath -WarningDays 7 -OutputFormat Markdown -CurrentDate ([datetime]'2026-03-01') -FailOnExpired

        $result.ExitCode | Should -Be 1
    }
}
