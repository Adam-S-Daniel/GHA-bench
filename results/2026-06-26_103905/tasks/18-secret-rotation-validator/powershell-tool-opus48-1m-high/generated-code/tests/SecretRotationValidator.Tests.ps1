#requires -Modules Pester

# Unit tests for the Secret Rotation Validator module.
#
# Methodology: red/green TDD. Each It below was introduced as a failing test
# first, then the minimum implementation was added to SecretRotationValidator.psm1
# to make it pass, then refactored. The grown suite is kept here as the
# regression net. (Note: the full pipeline is additionally exercised end-to-end
# through GitHub Actions / act in tests/Workflow.Tests.ps1.)

BeforeAll {
    # Resolve the module relative to this test file so the suite is location-independent.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SecretRotationValidator.psm1'
    Import-Module $script:ModulePath -Force

    # Shared helper: build a secret record quickly.
    function New-TestSecret {
        param($Name, $LastRotated, $PolicyDays, $RequiredBy = @())
        [pscustomobject]@{
            name               = $Name
            lastRotated        = $LastRotated
            rotationPolicyDays = $PolicyDays
            requiredBy         = $RequiredBy
        }
    }
}

Describe 'Get-SecretRotationStatus' {

    Context 'Classifying a single secret against a reference date' {

        It 'flags a secret whose rotation deadline has already passed as expired' {
            $secret = New-TestSecret 'db-password' '2026-01-01' 90 @('api', 'worker')   # deadline 2026-04-01
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.Status | Should -Be 'expired'
            $result.Name | Should -Be 'db-password'
            $result.ExpiryDate | Should -Be '2026-04-01'
            $result.DaysUntilExpiry | Should -BeLessThan 0
        }

        It 'flags a secret expiring inside the warning window as warning' {
            # deadline 2026-07-05, reference 2026-06-27 -> 8 days left, window 14 -> warning
            $secret = New-TestSecret 'tls-cert' '2026-04-06' 90
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.Status | Should -Be 'warning'
            $result.DaysUntilExpiry | Should -Be 8
        }

        It 'flags a secret well beyond the warning window as ok' {
            # deadline 2026-12-28, reference 2026-06-27 -> 184 days left -> ok
            $secret = New-TestSecret 'api-token' '2026-06-29' 182
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.Status | Should -Be 'ok'
        }

        It 'treats the exact warning-window boundary (days == WarningDays) as warning' {
            # deadline exactly WarningDays away counts as warning (inclusive boundary)
            $secret = New-TestSecret 'edge' '2026-06-13' 28   # deadline 2026-07-11, 14 days out
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 14
            $result.Status | Should -Be 'warning'
        }

        It 'treats a deadline exactly one day past the window as ok' {
            $secret = New-TestSecret 'edge2' '2026-06-12' 30   # deadline 2026-07-12, 15 days out
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 15
            $result.Status | Should -Be 'ok'
        }

        It 'treats a deadline that falls on the reference date as warning (0 days left)' {
            $secret = New-TestSecret 'today' '2026-03-29' 90   # deadline 2026-06-27
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 0
            $result.Status | Should -Be 'warning'
        }

        It 'normalises a missing requiredBy to an empty array' {
            $secret = [pscustomobject]@{ name = 'lonely'; lastRotated = '2026-06-01'; rotationPolicyDays = 30 }
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
            @($result.RequiredBy).Count | Should -Be 0
            $result.DaysUntilExpiry | Should -Be 4   # 2026-06-01 + 30 days = 2026-07-01
        }
    }

    Context 'Validating bad input' {

        It 'throws a meaningful error when name is missing' {
            $secret = [pscustomobject]@{ lastRotated = '2026-01-01'; rotationPolicyDays = 90 }
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14 } |
                Should -Throw -ExpectedMessage "*non-empty 'name'*"
        }

        It 'throws when rotationPolicyDays is not a positive integer' {
            $secret = New-TestSecret 'bad-policy' '2026-01-01' 0
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14 } |
                Should -Throw -ExpectedMessage "*invalid 'rotationPolicyDays'*"
        }

        It 'throws when lastRotated is not a valid yyyy-MM-dd date' {
            $secret = New-TestSecret 'bad-date' 'not-a-date' 90
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14 } |
                Should -Throw -ExpectedMessage "*Invalid lastRotated*"
        }
    }
}

Describe 'Import-SecretConfig' {

    BeforeAll {
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("srv-import-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:TmpRoot) { Remove-Item $script:TmpRoot -Recurse -Force }
    }

    It 'loads a valid configuration file' {
        $path = Join-Path $script:TmpRoot 'good.json'
        '{ "warningDays": 14, "secrets": [ { "name": "a", "lastRotated": "2026-01-01", "rotationPolicyDays": 90 } ] }' |
            Set-Content -LiteralPath $path -Encoding utf8
        $config = Import-SecretConfig -Path $path
        @($config.secrets).Count | Should -Be 1
        $config.warningDays | Should -Be 14
    }

    It 'throws a clear error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $script:TmpRoot 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error on invalid JSON' {
        $path = Join-Path $script:TmpRoot 'bad.json'
        '{ this is not json' | Set-Content -LiteralPath $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage '*invalid JSON*'
    }

    It "throws when the 'secrets' array is absent" {
        $path = Join-Path $script:TmpRoot 'no-secrets.json'
        '{ "warningDays": 14 }' | Set-Content -LiteralPath $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage "*must contain a 'secrets' array*"
    }
}

Describe 'New-RotationReport' {

    BeforeAll {
        $script:Config = [pscustomobject]@{
            referenceDate = '2026-06-27'
            warningDays   = 14
            secrets       = @(
                (New-TestSecret 'db-password' '2026-01-01' 90 @('api')),        # expired
                (New-TestSecret 'tls-cert'    '2026-04-06' 90 @('gateway')),    # warning (8 days)
                (New-TestSecret 'api-token'   '2026-06-29' 182 @('mobile')),    # ok
                (New-TestSecret 'signing-key' '2025-01-01' 90 @('ci'))          # expired (older)
            )
        }
    }

    It 'groups secrets by urgency using config defaults' {
        $report = New-RotationReport -Config $script:Config
        $report.Counts.Expired | Should -Be 2
        $report.Counts.Warning | Should -Be 1
        $report.Counts.Ok | Should -Be 1
        $report.Counts.Total | Should -Be 4
    }

    It 'sorts the expired group with the most-overdue secret first' {
        $report = New-RotationReport -Config $script:Config
        $report.Expired[0].Name | Should -Be 'signing-key'   # oldest / most negative days
    }

    It 'lets an explicit WarningDays parameter override the config window' {
        # Widen the window to 200 days: the previously-ok api-token becomes warning.
        $report = New-RotationReport -Config $script:Config -WarningDays 200
        $report.Counts.Ok | Should -Be 0
        ($report.Warning.Name -contains 'api-token') | Should -BeTrue
    }

    It 'lets an explicit ReferenceDate parameter override the config date' {
        # Move the clock back before any deadline -> everything ok.
        $report = New-RotationReport -Config $script:Config -ReferenceDate '2024-01-01'
        $report.Counts.Expired | Should -Be 0
    }

    It 'falls back to a default 14-day window when none is supplied' {
        $cfg = [pscustomobject]@{ referenceDate = '2026-06-27'; secrets = @((New-TestSecret 'x' '2026-04-06' 90)) }
        $report = New-RotationReport -Config $cfg
        $report.WarningDays | Should -Be 14
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $script:Config = [pscustomobject]@{
            referenceDate = '2026-06-27'
            warningDays   = 14
            secrets       = @(
                (New-TestSecret 'db-password' '2026-01-01' 90 @('api', 'worker')),
                (New-TestSecret 'tls-cert'    '2026-04-06' 90 @('gateway')),
                (New-TestSecret 'api-token'   '2026-06-29' 182 @('mobile'))
            )
        }
        $script:Report = New-RotationReport -Config $script:Config
    }

    Context 'markdown' {
        It 'renders a summary line and an expired table containing the expired secret' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match '# Secret Rotation Report'
            $md | Should -Match '1 expired, 1 warning, 1 ok \(3 total\)'
            $md | Should -Match '\| db-password \|'
            $md | Should -Match 'Required By'
        }

        It 'joins required-by services with a comma' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match 'api, worker'
        }

        It 'defaults to markdown when no format is given' {
            $md = Format-RotationReport -Report $script:Report
            $md | Should -Match '# Secret Rotation Report'
        }
    }

    Context 'json' {
        It 'emits valid JSON with counts and grouped secrets' {
            $json = Format-RotationReport -Report $script:Report -Format json
            $obj = $json | ConvertFrom-Json
            $obj.referenceDate | Should -Be '2026-06-27'
            $obj.warningDays | Should -Be 14
            $obj.counts.expired | Should -Be 1
            $obj.counts.warning | Should -Be 1
            $obj.counts.ok | Should -Be 1
            $obj.counts.total | Should -Be 3
            $obj.groups.expired[0].name | Should -Be 'db-password'
            $obj.groups.expired[0].status | Should -Be 'expired'
            @($obj.groups.expired[0].requiredBy) | Should -Contain 'worker'
        }
    }
}
