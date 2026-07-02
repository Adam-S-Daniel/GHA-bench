# Pester tests for the Secret Rotation Validator module.
# TDD: each Describe block below was written before its corresponding
# implementation existed in ../SecretRotationValidator.psm1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'SecretRotationValidator.psm1') -Force
}

Describe 'Get-SecretRotationStatus' {

    Context 'a secret rotated well within its policy window' {
        It 'is reported as Ok' {
            $result = Get-SecretRotationStatus -LastRotated (Get-Date '2026-06-01') `
                -RotationPolicyDays 90 -WarningDays 14 -Now (Get-Date '2026-06-15')

            $result.Status | Should -Be 'Ok'
            $result.DaysUntilDue | Should -Be 76
        }
    }

    Context 'a secret approaching its rotation deadline (inside the warning window)' {
        It 'is reported as Warning' {
            $result = Get-SecretRotationStatus -LastRotated (Get-Date '2026-01-01') `
                -RotationPolicyDays 90 -WarningDays 14 -Now (Get-Date '2026-03-27')

            # due date = 2026-04-01, now = 2026-03-27 -> 5 days until due, inside 14-day window
            $result.Status | Should -Be 'Warning'
            $result.DaysUntilDue | Should -Be 5
        }
    }

    Context 'a secret past its rotation policy window' {
        It 'is reported as Expired' {
            $result = Get-SecretRotationStatus -LastRotated (Get-Date '2026-01-01') `
                -RotationPolicyDays 30 -WarningDays 7 -Now (Get-Date '2026-03-01')

            $result.Status | Should -Be 'Expired'
            $result.DaysUntilDue | Should -Be -29
        }
    }

    Context 'a secret due exactly today' {
        It 'is reported as Expired (due date is not in the future)' {
            $result = Get-SecretRotationStatus -LastRotated (Get-Date '2026-01-01') `
                -RotationPolicyDays 30 -WarningDays 7 -Now (Get-Date '2026-01-31')

            $result.Status | Should -Be 'Expired'
            $result.DaysUntilDue | Should -Be 0
        }
    }

    Context 'invalid input' {
        It 'throws a meaningful error when RotationPolicyDays is not positive' {
            { Get-SecretRotationStatus -LastRotated (Get-Date) -RotationPolicyDays 0 -WarningDays 7 } |
                Should -Throw '*RotationPolicyDays*'
        }
    }
}

Describe 'New-SecretRotationReport' {

    BeforeAll {
        $script:Secrets = @(
            [PSCustomObject]@{
                Name               = 'db-prod-password'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 30
                RequiredBy         = @('billing-api', 'reporting-service')
            },
            [PSCustomObject]@{
                Name               = 'stripe-api-key'
                LastRotated        = '2026-03-20'
                RotationPolicyDays = 25
                RequiredBy         = @('billing-api')
            },
            [PSCustomObject]@{
                Name               = 'internal-ca-cert'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 365
                RequiredBy         = @('auth-service')
            }
        )
        $script:Now = Get-Date '2026-04-01'
    }

    It 'groups secrets into Expired, Warning, and Ok buckets' {
        $report = New-SecretRotationReport -Secrets $Secrets -WarningDays 14 -Now $Now

        $report.Expired.Name | Should -Contain 'db-prod-password'
        $report.Warning.Name | Should -Contain 'stripe-api-key'
        $report.Ok.Name | Should -Contain 'internal-ca-cert'
    }

    It 'includes rotation metadata and required-by services for each entry' {
        $report = New-SecretRotationReport -Secrets $Secrets -WarningDays 14 -Now $Now
        $entry = $report.Expired | Where-Object Name -eq 'db-prod-password'

        $entry.DaysUntilDue | Should -Be -60
        $entry.RequiredBy | Should -Be @('billing-api', 'reporting-service')
        $entry.DueDate | Should -Be (Get-Date '2026-01-31')
    }

    It 'reports summary counts matching each bucket size' {
        $report = New-SecretRotationReport -Secrets $Secrets -WarningDays 14 -Now $Now

        $report.Summary.ExpiredCount | Should -Be 1
        $report.Summary.WarningCount | Should -Be 1
        $report.Summary.OkCount | Should -Be 1
        $report.Summary.TotalCount | Should -Be 3
    }

    It 'throws a meaningful error when given an empty secrets collection' {
        { New-SecretRotationReport -Secrets @() -WarningDays 14 -Now $Now } |
            Should -Throw '*no secrets*'
    }
}

Describe 'Format-SecretRotationReport' {

    BeforeAll {
        $script:Secrets = @(
            [PSCustomObject]@{
                Name               = 'db-prod-password'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 30
                RequiredBy         = @('billing-api', 'reporting-service')
            },
            [PSCustomObject]@{
                Name               = 'stripe-api-key'
                LastRotated        = '2026-03-20'
                RotationPolicyDays = 25
                RequiredBy         = @('billing-api')
            },
            [PSCustomObject]@{
                Name               = 'internal-ca-cert'
                LastRotated        = '2026-01-01'
                RotationPolicyDays = 365
                RequiredBy         = @('auth-service')
            }
        )
        $script:Report = New-SecretRotationReport -Secrets $Secrets -WarningDays 14 -Now (Get-Date '2026-04-01')
    }

    Context 'Markdown format' {
        It 'renders a markdown table with a header row and one row per secret' {
            $markdown = Format-SecretRotationReport -Report $Report -Format Markdown

            $markdown | Should -Match '\| *Name *\| *Status *\| *Due Date *\| *Days Until Due *\| *Required By *\|'
            $markdown | Should -Match 'db-prod-password'
            $markdown | Should -Match 'stripe-api-key'
            $markdown | Should -Match 'internal-ca-cert'
        }

        It 'includes an urgency section header for each non-empty bucket' {
            $markdown = Format-SecretRotationReport -Report $Report -Format Markdown

            $markdown | Should -Match '(?m)^## Expired'
            $markdown | Should -Match '(?m)^## Warning'
            $markdown | Should -Match '(?m)^## Ok'
        }
    }

    Context 'JSON format' {
        It 'renders valid JSON that round-trips the summary counts' {
            $json = Format-SecretRotationReport -Report $Report -Format Json
            $parsed = $json | ConvertFrom-Json

            $parsed.Summary.ExpiredCount | Should -Be 1
            $parsed.Summary.WarningCount | Should -Be 1
            $parsed.Summary.OkCount | Should -Be 1
            $parsed.Expired[0].Name | Should -Be 'db-prod-password'
        }
    }

    Context 'invalid format' {
        It 'throws a meaningful error for an unsupported format' {
            { Format-SecretRotationReport -Report $Report -Format Xml } |
                Should -Throw
        }
    }
}

Describe 'Import-SecretConfig' {

    BeforeAll {
        $script:ValidConfigPath = Join-Path $TestDrive 'valid-secrets.json'
        @'
{
  "warningDays": 14,
  "secrets": [
    {
      "name": "db-prod-password",
      "lastRotated": "2026-01-01",
      "rotationPolicyDays": 30,
      "requiredBy": ["billing-api", "reporting-service"]
    }
  ]
}
'@ | Set-Content -Path $ValidConfigPath

        $script:MalformedConfigPath = Join-Path $TestDrive 'malformed.json'
        '{ not valid json' | Set-Content -Path $MalformedConfigPath

        $script:MissingFieldConfigPath = Join-Path $TestDrive 'missing-field.json'
        @'
{
  "warningDays": 14,
  "secrets": [
    { "name": "no-policy-secret", "lastRotated": "2026-01-01" }
  ]
}
'@ | Set-Content -Path $MissingFieldConfigPath
    }

    It 'loads secrets and the warning window from a valid config file' {
        $config = Import-SecretConfig -Path $ValidConfigPath

        $config.WarningDays | Should -Be 14
        $config.Secrets.Count | Should -Be 1
        $config.Secrets[0].Name | Should -Be 'db-prod-password'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the file contains malformed JSON' {
        { Import-SecretConfig -Path $MalformedConfigPath } |
            Should -Throw '*Invalid JSON*'
    }

    It 'throws a meaningful error when a secret is missing a required field' {
        { Import-SecretConfig -Path $MissingFieldConfigPath } |
            Should -Throw '*rotationPolicyDays*'
    }
}

Describe 'Invoke-SecretRotationValidator.ps1 (CLI)' {

    BeforeAll {
        $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Invoke-SecretRotationValidator.ps1'
        $script:SampleConfigPath = Join-Path $PSScriptRoot '..' 'fixtures' 'sample-secrets.json'
    }

    It 'exits 0 and prints a Markdown report when no secrets are expired' {
        $output = & $ScriptPath -ConfigPath $SampleConfigPath -Now '2026-01-15' -FailOnExpired:$false 2>&1
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match '# Secret Rotation Report'
    }

    It 'exits 1 when an expired secret is present and -FailOnExpired is set' {
        & $ScriptPath -ConfigPath $SampleConfigPath -Now '2026-07-01' -FailOnExpired:$true *> $null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 0 for the same expired scenario when -FailOnExpired is disabled' {
        & $ScriptPath -ConfigPath $SampleConfigPath -Now '2026-07-01' -FailOnExpired:$false *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'renders JSON output when -Format Json is passed' {
        $output = & $ScriptPath -ConfigPath $SampleConfigPath -Now '2026-07-01' -Format Json -FailOnExpired:$false
        $parsed = ($output -join "`n") | ConvertFrom-Json

        $parsed.Summary.TotalCount | Should -Be 4
    }

    It 'exits 2 with a meaningful error when the config file does not exist' {
        & $ScriptPath -ConfigPath (Join-Path $TestDrive 'missing.json') -FailOnExpired:$false *> $null
        $LASTEXITCODE | Should -Be 2
    }

    It 'writes the report to -OutputPath when provided' {
        $outPath = Join-Path $TestDrive 'report.md'
        & $ScriptPath -ConfigPath $SampleConfigPath -Now '2026-01-15' -OutputPath $outPath -FailOnExpired:$false *> $null

        Test-Path $outPath | Should -BeTrue
        Get-Content $outPath -Raw | Should -Match '# Secret Rotation Report'
    }
}
