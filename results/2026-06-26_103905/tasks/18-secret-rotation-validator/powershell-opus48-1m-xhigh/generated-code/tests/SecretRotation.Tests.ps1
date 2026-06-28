# SecretRotation.Tests.ps1
#
# Pester (v5) unit tests for the secret-rotation-validator core logic.
#
# TDD approach: each Describe block was written test-first (red), then the
# minimum implementation was added to SecretRotation.psm1 to make it pass
# (green), then refactored. The module is imported once in BeforeAll.
#
# All dates are evaluated against a fixed "as-of" reference date so the tests
# are fully deterministic and never depend on the wall clock.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'SecretRotation.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-SecretStatus' {

    # A secret whose rotation deadline is already in the past is "expired".
    It 'classifies a secret past its rotation deadline as expired' {
        $secret = [pscustomobject]@{
            name               = 'DB_PASSWORD'
            lastRotated        = '2025-01-01'
            rotationPolicyDays = 90
            requiredBy         = @('api')
        }
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.status | Should -Be 'expired'
    }

    # A secret whose deadline falls inside the warning window is "warning".
    It 'classifies a secret expiring within the warning window as warning' {
        $secret = [pscustomobject]@{
            name               = 'SIGNING_KEY'
            lastRotated        = '2025-05-20'
            rotationPolicyDays = 14
            requiredBy         = @('signer')
        }
        # expires 2025-06-03; as-of 2025-06-01 -> 2 days left, window 14 -> warning
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.status | Should -Be 'warning'
    }

    # A secret with plenty of life left is "ok".
    It 'classifies a secret outside the warning window as ok' {
        $secret = [pscustomobject]@{
            name               = 'WEBHOOK_SECRET'
            lastRotated        = '2025-05-01'
            rotationPolicyDays = 90
            requiredBy         = @('webhooks')
        }
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.status | Should -Be 'ok'
    }

    # Boundary: a deadline exactly on the as-of date is still "warning"
    # (the secret has not lapsed yet -- it expires today).
    It 'treats a deadline exactly on the as-of date as warning, not expired' {
        $secret = [pscustomobject]@{
            name               = 'EDGE_TODAY'
            lastRotated        = '2025-05-02'
            rotationPolicyDays = 30
            requiredBy         = @('edge')
        }
        # expires 2025-06-01 == as-of -> 0 days left -> warning
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.status | Should -Be 'warning'
    }

    # Boundary: a deadline exactly one day past the window edge is "ok".
    It 'treats a deadline one day beyond the window as ok' {
        $secret = [pscustomobject]@{
            name               = 'EDGE_OUT'
            lastRotated        = '2025-05-18'
            rotationPolicyDays = 30
            requiredBy         = @('edge')
        }
        # expires 2025-06-17; as-of 2025-06-01 -> 16 days left, window 14 -> ok
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.status | Should -Be 'ok'
    }

    # The status object should carry the computed deadline and days-remaining
    # so reports can present them without recomputation.
    It 'returns the computed expiry date and days remaining' {
        $secret = [pscustomobject]@{
            name               = 'API_KEY'
            lastRotated        = '2025-02-15'
            rotationPolicyDays = 90
            requiredBy         = @('api')
        }
        $result = Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14
        $result.expiresOn        | Should -Be '2025-05-16'
        $result.daysUntilExpiry  | Should -Be -16
        $result.name             | Should -Be 'API_KEY'
        $result.requiredBy       | Should -Be @('api')
    }

    It 'throws a meaningful error for an invalid date' {
        $secret = [pscustomobject]@{
            name = 'BAD'; lastRotated = 'not-a-date'; rotationPolicyDays = 30; requiredBy = @()
        }
        { Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14 } |
            Should -Throw -ExpectedMessage '*Invalid date*'
    }

    It 'throws a meaningful error for a non-positive rotation policy' {
        $secret = [pscustomobject]@{
            name = 'BAD'; lastRotated = '2025-01-01'; rotationPolicyDays = 0; requiredBy = @()
        }
        { Get-SecretStatus -Secret $secret -AsOf '2025-06-01' -WarningWindowDays 14 } |
            Should -Throw -ExpectedMessage '*non-positive*'
    }
}

Describe 'Import-SecretConfig' {

    BeforeAll {
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("srv-cfg-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $script:TmpDir) { Remove-Item -Recurse -Force $script:TmpDir }
    }

    It 'loads a valid config file and exposes its secrets and settings' {
        $path = Join-Path $script:TmpDir 'valid.json'
        @'
{
  "warningWindowDays": 14,
  "asOf": "2025-06-01",
  "secrets": [
    { "name": "A", "lastRotated": "2025-05-01", "rotationPolicyDays": 90, "requiredBy": ["svc"] }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $cfg = Import-SecretConfig -Path $path
        $cfg.warningWindowDays | Should -Be 14
        $cfg.asOf              | Should -Be '2025-06-01'
        @($cfg.secrets).Count  | Should -Be 1
        $cfg.secrets[0].name   | Should -Be 'A'
    }

    It 'throws a clear error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $script:TmpDir 'nope.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error for malformed JSON' {
        $path = Join-Path $script:TmpDir 'bad.json'
        'this is { not json' | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage '*Failed to parse*'
    }

    It 'throws when the secrets array is missing' {
        $path = Join-Path $script:TmpDir 'nosecrets.json'
        '{ "warningWindowDays": 7 }' | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage "*'secrets'*"
    }
}

Describe 'Get-RotationReport' {

    BeforeAll {
        # An inline config object exercising every urgency bucket, with a fixed
        # as-of date for determinism.
        $script:Config = [pscustomobject]@{
            warningWindowDays = 14
            asOf              = '2025-06-01'
            secrets           = @(
                [pscustomobject]@{ name = 'DB_PASSWORD';    lastRotated = '2025-01-01'; rotationPolicyDays = 90; requiredBy = @('api','worker') }  # expired
                [pscustomobject]@{ name = 'API_KEY';        lastRotated = '2025-02-15'; rotationPolicyDays = 90; requiredBy = @('api') }            # expired
                [pscustomobject]@{ name = 'TLS_CERT';       lastRotated = '2025-04-05'; rotationPolicyDays = 60; requiredBy = @('gateway') }        # warning
                [pscustomobject]@{ name = 'SIGNING_KEY';    lastRotated = '2025-05-20'; rotationPolicyDays = 14; requiredBy = @('signer') }         # warning
                [pscustomobject]@{ name = 'WEBHOOK_SECRET'; lastRotated = '2025-05-01'; rotationPolicyDays = 90; requiredBy = @('webhooks') }       # ok
            )
        }
    }

    It 'computes a correct urgency summary' {
        $report = Get-RotationReport -Config $script:Config
        $report.summary.expired | Should -Be 2
        $report.summary.warning | Should -Be 2
        $report.summary.ok      | Should -Be 1
        $report.summary.total   | Should -Be 5
    }

    It 'groups secrets by urgency' {
        $report = Get-RotationReport -Config $script:Config
        @($report.groups.expired).Count | Should -Be 2
        @($report.groups.warning).Count | Should -Be 2
        @($report.groups.ok).Count      | Should -Be 1
        $report.groups.ok[0].name       | Should -Be 'WEBHOOK_SECRET'
    }

    It 'echoes the effective as-of date and warning window' {
        $report = Get-RotationReport -Config $script:Config
        $report.asOf              | Should -Be '2025-06-01'
        $report.warningWindowDays | Should -Be 14
    }

    It 'lets explicit parameters override config-supplied settings' {
        # Widen the window to 120 days: both former 'expired'... stay expired, but
        # WEBHOOK_SECRET (59 days out) moves from ok -> warning.
        $report = Get-RotationReport -Config $script:Config -WarningWindowDays 120 -AsOf '2025-06-01'
        $report.warningWindowDays | Should -Be 120
        $report.summary.ok        | Should -Be 0
        $report.summary.warning   | Should -Be 3
    }

    It 'sorts within a group by most-urgent (fewest days remaining) first' {
        $report = Get-RotationReport -Config $script:Config
        # API_KEY expired 2025-05-16 (-16), DB_PASSWORD expired 2025-04-01 (-61):
        # DB_PASSWORD is more overdue, so it should come first.
        $report.groups.expired[0].name | Should -Be 'DB_PASSWORD'
        $report.groups.expired[1].name | Should -Be 'API_KEY'
    }

    It 'defaults the warning window to 30 days when neither config nor parameter supplies one' {
        $cfg = [pscustomobject]@{
            asOf    = '2025-06-01'
            secrets = @(
                [pscustomobject]@{ name = 'X'; lastRotated = '2025-05-10'; rotationPolicyDays = 40; requiredBy = @() } # expires 2025-06-19 -> 18 days
            )
        }
        $report = Get-RotationReport -Config $cfg
        $report.warningWindowDays | Should -Be 30
        $report.summary.warning   | Should -Be 1   # 18 <= 30
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $script:Config = [pscustomobject]@{
            warningWindowDays = 14
            asOf              = '2025-06-01'
            secrets           = @(
                [pscustomobject]@{ name = 'DB_PASSWORD';    lastRotated = '2025-01-01'; rotationPolicyDays = 90; requiredBy = @('api','worker') }
                [pscustomobject]@{ name = 'WEBHOOK_SECRET'; lastRotated = '2025-05-01'; rotationPolicyDays = 90; requiredBy = @('webhooks') }
            )
        }
        $script:Report = Get-RotationReport -Config $script:Config
    }

    It 'renders a markdown report with a heading, table, and the secret rows' {
        $md = Format-RotationReport -Report $script:Report -Format markdown
        $md | Should -Match '# Secret Rotation Report'
        $md | Should -Match '\| Secret \| Status \|'   # table header
        $md | Should -Match 'DB_PASSWORD'
        $md | Should -Match 'expired'
        $md | Should -Match 'WEBHOOK_SECRET'
        $md | Should -Match 'api, worker'               # required-by services joined
    }

    It 'renders valid JSON that round-trips to the same summary' {
        $json = Format-RotationReport -Report $script:Report -Format json
        $parsed = $json | ConvertFrom-Json
        $parsed.summary.expired | Should -Be 1
        $parsed.summary.ok      | Should -Be 1
        $parsed.summary.total   | Should -Be 2
        $parsed.asOf            | Should -Be '2025-06-01'
        @($parsed.secrets).Count | Should -Be 2
    }

    It 'rejects an unknown output format' {
        { Format-RotationReport -Report $script:Report -Format xml } |
            Should -Throw -ExpectedMessage '*Unsupported*'
    }
}
