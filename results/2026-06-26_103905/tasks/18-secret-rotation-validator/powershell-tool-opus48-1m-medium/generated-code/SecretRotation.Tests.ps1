#requires -Modules Pester

# Pester tests for the Secret Rotation Validator.
# Red/Green TDD: each Describe block was written to fail first, then the
# corresponding function in SecretRotation.psm1 was implemented to make it pass.

BeforeAll {
    # Import the module under test from the same directory as this test file.
    $ModulePath = Join-Path $PSScriptRoot 'SecretRotation.psm1'
    Import-Module $ModulePath -Force

    # A fixed "now" so tests are deterministic regardless of when they run.
    $script:RefDate = [datetime]'2026-06-26'

    # Helper to build a secret object quickly.
    function New-TestSecret {
        param($Name, $LastRotated, $PolicyDays, $RequiredBy = @())
        [pscustomobject]@{
            name              = $Name
            lastRotated       = $LastRotated
            rotationPolicyDays = $PolicyDays
            requiredBy        = $RequiredBy
        }
    }
}

Describe 'Get-SecretRotationStatus' {

    Context 'classification of a single secret' {
        It 'marks a secret past its policy window as expired' {
            # Last rotated 100 days ago, policy 30 days -> expired 70 days ago.
            $secret = New-TestSecret -Name 'db-password' -LastRotated '2026-03-18' -PolicyDays 30
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7
            $result.status | Should -Be 'expired'
            $result.daysUntilExpiry | Should -BeLessThan 0
        }

        It 'marks a secret inside the warning window as warning' {
            # Rotated 27 days ago, policy 30 -> expires in 3 days, warning window 7.
            $secret = New-TestSecret -Name 'api-key' -LastRotated '2026-05-30' -PolicyDays 30
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7
            $result.status | Should -Be 'warning'
            $result.daysUntilExpiry | Should -Be 3
        }

        It 'marks a secret well within policy as ok' {
            # Rotated 1 day ago, policy 90 -> expires in 89 days.
            $secret = New-TestSecret -Name 'tls-cert' -LastRotated '2026-06-25' -PolicyDays 90
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7
            $result.status | Should -Be 'ok'
            $result.daysUntilExpiry | Should -Be 89
        }

        It 'treats a secret expiring exactly today (0 days) as warning' {
            $secret = New-TestSecret -Name 'edge-zero' -LastRotated '2026-05-27' -PolicyDays 30
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7
            $result.daysUntilExpiry | Should -Be 0
            $result.status | Should -Be 'warning'
        }

        It 'preserves name and requiredBy metadata in the result' {
            $secret = New-TestSecret -Name 'svc-token' -LastRotated '2026-06-25' -PolicyDays 90 -RequiredBy @('billing','auth')
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7
            $result.name | Should -Be 'svc-token'
            $result.requiredBy | Should -Be @('billing','auth')
        }
    }

    Context 'input validation' {
        It 'throws a meaningful error when rotationPolicyDays is not positive' {
            $secret = New-TestSecret -Name 'bad-policy' -LastRotated '2026-06-25' -PolicyDays 0
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7 } |
                Should -Throw -ExpectedMessage "*rotationPolicyDays*"
        }

        It 'throws a meaningful error when lastRotated is not a valid date' {
            $secret = New-TestSecret -Name 'bad-date' -LastRotated 'not-a-date' -PolicyDays 30
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate $script:RefDate -WarningDays 7 } |
                Should -Throw -ExpectedMessage "*lastRotated*"
        }
    }
}

Describe 'New-RotationReport' {

    BeforeAll {
        $script:Secrets = @(
            New-TestSecret -Name 'expired-1' -LastRotated '2026-01-01' -PolicyDays 30 -RequiredBy @('web')
            New-TestSecret -Name 'warning-1' -LastRotated '2026-05-30' -PolicyDays 30 -RequiredBy @('api')
            New-TestSecret -Name 'ok-1'      -LastRotated '2026-06-25' -PolicyDays 90 -RequiredBy @('batch')
            New-TestSecret -Name 'expired-2' -LastRotated '2026-02-01' -PolicyDays 30 -RequiredBy @('auth')
        )
    }

    It 'groups secrets by urgency' {
        $report = New-RotationReport -Secrets $script:Secrets -ReferenceDate $script:RefDate -WarningDays 7
        $report.expired.Count | Should -Be 2
        $report.warning.Count | Should -Be 1
        $report.ok.Count      | Should -Be 1
    }

    It 'reports accurate summary counts' {
        $report = New-RotationReport -Secrets $script:Secrets -ReferenceDate $script:RefDate -WarningDays 7
        $report.summary.total   | Should -Be 4
        $report.summary.expired | Should -Be 2
        $report.summary.warning | Should -Be 1
        $report.summary.ok      | Should -Be 1
    }

    It 'sorts expired secrets most-overdue first' {
        $report = New-RotationReport -Secrets $script:Secrets -ReferenceDate $script:RefDate -WarningDays 7
        # expired-1 (Jan 1) is more overdue than expired-2 (Feb 1).
        $report.expired[0].name | Should -Be 'expired-1'
    }

    It 'throws when the secrets collection is empty' {
        { New-RotationReport -Secrets @() -ReferenceDate $script:RefDate -WarningDays 7 } |
            Should -Throw -ExpectedMessage "*no secrets*"
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $secrets = @(
            New-TestSecret -Name 'expired-1' -LastRotated '2026-01-01' -PolicyDays 30 -RequiredBy @('web')
            New-TestSecret -Name 'warning-1' -LastRotated '2026-05-30' -PolicyDays 30 -RequiredBy @('api','cdn')
            New-TestSecret -Name 'ok-1'      -LastRotated '2026-06-25' -PolicyDays 90 -RequiredBy @('batch')
        )
        $script:Report = New-RotationReport -Secrets $secrets -ReferenceDate $script:RefDate -WarningDays 7
    }

    Context 'markdown format' {
        It 'produces a markdown table with a header row' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match '\| Secret \| Status \| Days Until Expiry \| Required By \|'
        }

        It 'includes every secret name in the markdown output' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match 'expired-1'
            $md | Should -Match 'warning-1'
            $md | Should -Match 'ok-1'
        }

        It 'renders requiredBy services as a comma-separated list' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match 'api, cdn'
        }

        It 'includes a summary line with the counts' {
            $md = Format-RotationReport -Report $script:Report -Format markdown
            $md | Should -Match '1 expired'
            $md | Should -Match '1 warning'
            $md | Should -Match '1 ok'
        }
    }

    Context 'json format' {
        It 'produces valid JSON that round-trips' {
            $json = Format-RotationReport -Report $script:Report -Format json
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'preserves the grouped structure in JSON' {
            $json = Format-RotationReport -Report $script:Report -Format json
            $parsed = $json | ConvertFrom-Json
            $parsed.summary.total | Should -Be 3
            $parsed.expired[0].name | Should -Be 'expired-1'
        }
    }

    Context 'unknown format' {
        It 'throws a meaningful error for an unsupported format' {
            { Format-RotationReport -Report $script:Report -Format xml } |
                Should -Throw
        }
    }
}

Describe 'Import-SecretConfig' {

    It 'loads secrets from a JSON config file' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("secrets-" + [guid]::NewGuid() + ".json")
        @{
            secrets = @(
                @{ name = 'db'; lastRotated = '2026-01-01'; rotationPolicyDays = 30; requiredBy = @('web') }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp
        try {
            $secrets = Import-SecretConfig -Path $tmp
            $secrets.Count | Should -Be 1
            $secrets[0].name | Should -Be 'db'
        } finally {
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path '/no/such/file.json' } |
            Should -Throw -ExpectedMessage "*not found*"
    }

    It 'throws a meaningful error when the JSON is malformed' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bad-" + [guid]::NewGuid() + ".json")
        Set-Content -Path $tmp -Value '{ this is not json'
        try {
            { Import-SecretConfig -Path $tmp } | Should -Throw -ExpectedMessage "*parse*"
        } finally {
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }
}
