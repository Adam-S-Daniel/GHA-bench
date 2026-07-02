# Unit tests for SecretRotationValidator.ps1
#
# TDD approach: each Describe block was written as a failing (red) test first,
# then the minimum implementation was added to SecretRotationValidator.ps1 to
# make it pass (green), followed by refactoring.
#
# All date math is deterministic: tests pass an explicit -ReferenceDate instead
# of relying on the wall clock.

BeforeAll {
    # Dot-source the script with no arguments: this loads the functions
    # without executing the CLI entry point.
    . (Join-Path $PSScriptRoot '..' 'SecretRotationValidator.ps1')

    # Shared reference "today" for deterministic assertions.
    $script:RefDate = [datetime]'2026-07-01'
}

Describe 'Get-SecretRotationStatus' {

    It 'classifies a secret past its rotation deadline as expired' {
        $secret = [pscustomobject]@{
            name         = 'db-password'
            lastRotated  = '2026-01-01'
            rotationDays = 90
            requiredBy   = @('billing-api')
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14
        $status.Urgency | Should -Be 'expired'
        $status.ExpiryDate | Should -Be ([datetime]'2026-04-01')
        $status.DaysRemaining | Should -Be -91
    }

    It 'classifies a secret expiring today as expired (boundary)' {
        $secret = [pscustomobject]@{
            name = 'webhook-token'; lastRotated = '2026-04-02'; rotationDays = 90; requiredBy = @()
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14
        $status.Urgency | Should -Be 'expired'
        $status.DaysRemaining | Should -Be 0
    }

    It 'classifies a secret inside the warning window as warning' {
        $secret = [pscustomobject]@{
            name = 'api-key'; lastRotated = '2026-06-25'; rotationDays = 10; requiredBy = @('gateway')
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14
        $status.Urgency | Should -Be 'warning'
        $status.DaysRemaining | Should -Be 4
    }

    It 'classifies a secret expiring exactly at the window edge as warning (boundary)' {
        # Expiry = ref + window exactly.
        $secret = [pscustomobject]@{
            name = 'edge'; lastRotated = '2026-07-01'; rotationDays = 14; requiredBy = @()
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14
        $status.Urgency | Should -Be 'warning'
        $status.DaysRemaining | Should -Be 14
    }

    It 'classifies a secret outside the warning window as ok' {
        $secret = [pscustomobject]@{
            name = 'tls-cert'; lastRotated = '2026-06-01'; rotationDays = 365; requiredBy = @('web')
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14
        $status.Urgency | Should -Be 'ok'
        $status.DaysRemaining | Should -Be 335
    }

    It 'respects a custom warning window' {
        # 4 days remaining is "ok" when the window is only 2 days.
        $secret = [pscustomobject]@{
            name = 'api-key'; lastRotated = '2026-06-25'; rotationDays = 10; requiredBy = @()
        }
        $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 2
        $status.Urgency | Should -Be 'ok'
    }

    It 'throws a meaningful error for an invalid lastRotated date' {
        $secret = [pscustomobject]@{
            name = 'bad'; lastRotated = 'not-a-date'; rotationDays = 30; requiredBy = @()
        }
        { Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14 } |
            Should -Throw "*Secret 'bad'*invalid lastRotated*"
    }

    It 'throws a meaningful error for a non-positive rotation policy' {
        $secret = [pscustomobject]@{
            name = 'bad'; lastRotated = '2026-01-01'; rotationDays = 0; requiredBy = @()
        }
        { Get-SecretRotationStatus -Secret $secret -ReferenceDate $RefDate -WarningWindowDays 14 } |
            Should -Throw "*Secret 'bad'*rotationDays must be a positive integer*"
    }
}

Describe 'Import-SecretConfig' {

    It 'loads secrets from a JSON config file' {
        $secrets = Import-SecretConfig -Path (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json')
        $secrets.Count | Should -Be 5
        $secrets[0].name | Should -Be 'db-password'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw '*Config file not found*missing.json*'
    }

    It 'throws a meaningful error for malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{ this is not json'
        { Import-SecretConfig -Path $bad } | Should -Throw '*not valid JSON*'
    }

    It 'throws a meaningful error when a secret is missing required fields' {
        $bad = Join-Path $TestDrive 'incomplete.json'
        Set-Content -Path $bad -Value '{"secrets":[{"name":"x","lastRotated":"2026-01-01"}]}'
        { Import-SecretConfig -Path $bad } | Should -Throw "*Secret 'x'*missing required field 'rotationDays'*"
    }

    It 'throws a meaningful error when the top-level secrets array is missing' {
        $bad = Join-Path $TestDrive 'nosecrets.json'
        Set-Content -Path $bad -Value '{"other": []}'
        { Import-SecretConfig -Path $bad } | Should -Throw "*must contain a 'secrets' array*"
    }
}

Describe 'Get-RotationReport' {

    BeforeAll {
        $secrets = Import-SecretConfig -Path (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json')
        $script:Report = Get-RotationReport -Secrets $secrets -ReferenceDate $RefDate -WarningWindowDays 14
    }

    It 'groups secrets by urgency' {
        $Report.Expired.Count | Should -Be 2
        $Report.Warning.Count | Should -Be 2
        $Report.Ok.Count | Should -Be 1
    }

    It 'sorts each group by days remaining, most urgent first' {
        $Report.Expired[0].Name | Should -Be 'db-password'    # -91 days
        $Report.Expired[1].Name | Should -Be 'webhook-token'  # 0 days
        $Report.Warning[0].Name | Should -Be 'jwt-secret'     # 3 days
        $Report.Warning[1].Name | Should -Be 'api-key'        # 4 days
    }

    It 'carries summary counts' {
        $Report.Summary.Total | Should -Be 5
        $Report.Summary.Expired | Should -Be 2
        $Report.Summary.Warning | Should -Be 2
        $Report.Summary.Ok | Should -Be 1
    }
}

Describe 'Output formats' {

    BeforeAll {
        $secrets = Import-SecretConfig -Path (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json')
        $script:Report = Get-RotationReport -Secrets $secrets -ReferenceDate $RefDate -WarningWindowDays 14
    }

    Context 'ConvertTo-MarkdownReport' {

        BeforeAll { $script:Md = ConvertTo-MarkdownReport -Report $Report }

        It 'renders a markdown table with a header row' {
            $Md | Should -Match '\| Secret \| Urgency \| Expiry Date \| Days Remaining \| Required By \|'
        }

        It 'renders exact rows for each secret, grouped and ordered by urgency' {
            $Md | Should -Match ([regex]::Escape('| db-password | EXPIRED | 2026-04-01 | -91 | billing-api, reporting |'))
            $Md | Should -Match ([regex]::Escape('| webhook-token | EXPIRED | 2026-07-01 | 0 | ci-pipeline |'))
            $Md | Should -Match ([regex]::Escape('| jwt-secret | WARNING | 2026-07-04 | 3 | auth-service, gateway |'))
            $Md | Should -Match ([regex]::Escape('| api-key | WARNING | 2026-07-05 | 4 | gateway |'))
            $Md | Should -Match ([regex]::Escape('| tls-cert | OK | 2027-06-01 | 335 | web-frontend |'))
        }

        It 'includes a summary line with exact counts' {
            $Md | Should -Match ([regex]::Escape('**Summary:** 2 expired, 2 warning, 1 ok (5 total)'))
        }
    }

    Context 'ConvertTo-JsonReport' {

        BeforeAll { $script:Parsed = ConvertTo-JsonReport -Report $Report | ConvertFrom-Json }

        It 'produces valid JSON grouped by urgency' {
            $Parsed.expired.Count | Should -Be 2
            $Parsed.warning.Count | Should -Be 2
            $Parsed.ok.Count | Should -Be 1
        }

        It 'includes full metadata per secret' {
            $first = $Parsed.expired[0]
            $first.name | Should -Be 'db-password'
            $first.expiryDate | Should -Be '2026-04-01'
            $first.daysRemaining | Should -Be -91
            $first.requiredBy | Should -Be @('billing-api', 'reporting')
        }

        It 'includes summary counts' {
            $Parsed.summary.expired | Should -Be 2
            $Parsed.summary.warning | Should -Be 2
            $Parsed.summary.ok | Should -Be 1
            $Parsed.summary.total | Should -Be 5
        }
    }
}

Describe 'CLI entry point' {

    # The CLI is exercised in a child pwsh process (exactly how CI invokes it)
    # so exit codes and stream separation behave as they do in production.
    # NOTE: variables here deliberately avoid the names of the script's own
    # param() block ($ConfigPath, $Format, ...) — dot-sourcing the script in
    # the top-level BeforeAll defines those (empty) in an ancestor scope, and
    # they would shadow same-named test variables.
    BeforeAll {
        $script:CliScript = Join-Path $PSScriptRoot '..' 'SecretRotationValidator.ps1'
        $script:CliConfig = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json'
        function script:Invoke-Cli {
            param([string[]]$CliArgs)
            $stdout = & pwsh -NoProfile -File $script:CliScript @CliArgs 2>$null
            [pscustomobject]@{ Output = ($stdout | Out-String); ExitCode = $LASTEXITCODE }
        }
    }

    It 'emits a markdown report when -Format markdown' {
        $result = Invoke-Cli @('-ConfigPath', $CliConfig, '-ReferenceDate', '2026-07-01', '-Format', 'markdown')
        $result.Output | Should -Match ([regex]::Escape('| db-password | EXPIRED | 2026-04-01 | -91 | billing-api, reporting |'))
        $result.ExitCode | Should -Be 0
    }

    It 'emits a JSON report when -Format json' {
        $result = Invoke-Cli @('-ConfigPath', $CliConfig, '-ReferenceDate', '2026-07-01', '-Format', 'json')
        ($result.Output | ConvertFrom-Json).summary.expired | Should -Be 2
        $result.ExitCode | Should -Be 0
    }

    It 'exits with code 2 when -FailOnExpired and expired secrets exist' {
        $result = Invoke-Cli @('-ConfigPath', $CliConfig, '-ReferenceDate', '2026-07-01', '-Format', 'json', '-FailOnExpired')
        $result.ExitCode | Should -Be 2
    }

    It 'exits zero with -FailOnExpired when nothing is expired' {
        $okConfig = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets-ok.json'
        $result = Invoke-Cli @('-ConfigPath', $okConfig, '-ReferenceDate', '2026-07-01', '-Format', 'json', '-FailOnExpired')
        $result.ExitCode | Should -Be 0
    }

    It 'exits with code 1 and a meaningful error for a missing config file' {
        $stderr = & pwsh -NoProfile -File $CliScript -ConfigPath '/nonexistent/nope.json' 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $stderr | Should -Match 'Config file not found'
    }

    It 'rejects an unknown format via parameter validation' {
        & pwsh -NoProfile -File $CliScript -ConfigPath $CliConfig -Format xml 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
