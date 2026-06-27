# Pester tests for the Secret Rotation Validator module.
# Developed with red/green TDD: each Describe block was written as a failing
# test first, then the minimum module code was added to make it pass.

BeforeAll {
    # Resolve the module relative to this test file so tests are location-independent.
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/SecretRotationValidator.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-SecretRotationStatus' {

    Context 'classification of a single secret' {

        It 'flags a secret whose due date is in the past as expired' {
            $secret = [pscustomobject]@{
                name               = 'db-password'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 90
                requiredBy         = @('api')
            }
            # Reference date is well past lastRotated + 90 days (2026-04-01).
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-01' -WarningWindowDays 14
            $result.status | Should -Be 'expired'
            $result.daysUntilDue | Should -Be -61
        }

        It 'flags a secret due inside the warning window as warning' {
            $secret = [pscustomobject]@{
                name               = 'api-key'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 90
                requiredBy         = @('worker')
            }
            # Due 2026-04-01; reference 2026-03-25 => 7 days until due, within 14-day window.
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-03-25' -WarningWindowDays 14
            $result.status | Should -Be 'warning'
            $result.daysUntilDue | Should -Be 7
        }

        It 'flags a secret due well in the future as ok' {
            $secret = [pscustomobject]@{
                name               = 'tls-cert'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 90
                requiredBy         = @('ingress')
            }
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-01-10' -WarningWindowDays 14
            $result.status | Should -Be 'ok'
            $result.daysUntilDue | Should -Be 81
        }

        It 'treats a secret due exactly on the warning boundary as warning' {
            $secret = [pscustomobject]@{
                name               = 'edge'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 90
                requiredBy         = @('svc')
            }
            # Due 2026-04-01; reference 2026-03-18 => exactly 14 days.
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-03-18' -WarningWindowDays 14
            $result.status | Should -Be 'warning'
        }

        It 'carries through the secret name, policy and requiredBy services' {
            $secret = [pscustomobject]@{
                name               = 'svc-token'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 30
                requiredBy         = @('api', 'cron')
            }
            $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-01-15' -WarningWindowDays 7
            $result.name | Should -Be 'svc-token'
            $result.rotationPolicyDays | Should -Be 30
            $result.requiredBy | Should -Be @('api', 'cron')
            $result.dueDate | Should -Be '2026-01-31'
        }
    }

    Context 'input validation' {

        It 'throws a meaningful error when lastRotated is not a valid date' {
            $secret = [pscustomobject]@{
                name               = 'broken'
                lastRotated        = 'not-a-date'
                rotationPolicyDays = 90
                requiredBy         = @('x')
            }
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-01-01' -WarningWindowDays 14 } |
                Should -Throw "*Invalid 'lastRotated' date*"
        }

        It 'throws a meaningful error when rotationPolicyDays is not positive' {
            $secret = [pscustomobject]@{
                name               = 'zero-policy'
                lastRotated        = '2026-01-01'
                rotationPolicyDays = 0
                requiredBy         = @('x')
            }
            { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-01-01' -WarningWindowDays 14 } |
                Should -Throw "*rotationPolicyDays*must be a positive*"
        }
    }
}

Describe 'New-RotationReport' {

    BeforeAll {
        $script:secrets = @(
            [pscustomobject]@{ name = 'expired-1'; lastRotated = '2026-01-01'; rotationPolicyDays = 30;  requiredBy = @('api') }
            [pscustomobject]@{ name = 'warning-1'; lastRotated = '2026-01-01'; rotationPolicyDays = 90;  requiredBy = @('worker') }
            [pscustomobject]@{ name = 'ok-1';      lastRotated = '2026-01-01'; rotationPolicyDays = 365; requiredBy = @('batch') }
        )
    }

    It 'groups secrets into expired, warning and ok buckets' {
        $report = New-RotationReport -Secrets $script:secrets -ReferenceDate '2026-03-25' -WarningWindowDays 14
        $report.expired.name | Should -Be 'expired-1'
        $report.warning.name | Should -Be 'warning-1'
        $report.ok.name      | Should -Be 'ok-1'
    }

    It 'reports summary counts and the parameters used' {
        $report = New-RotationReport -Secrets $script:secrets -ReferenceDate '2026-03-25' -WarningWindowDays 14
        $report.summary.expired | Should -Be 1
        $report.summary.warning | Should -Be 1
        $report.summary.ok      | Should -Be 1
        $report.summary.total   | Should -Be 3
        $report.referenceDate     | Should -Be '2026-03-25'
        $report.warningWindowDays | Should -Be 14
    }

    It 'sorts expired secrets most-overdue first' {
        $secrets = @(
            [pscustomobject]@{ name = 'mild';   lastRotated = '2026-02-01'; rotationPolicyDays = 30; requiredBy = @('a') }
            [pscustomobject]@{ name = 'severe'; lastRotated = '2026-01-01'; rotationPolicyDays = 30; requiredBy = @('b') }
        )
        $report = New-RotationReport -Secrets $secrets -ReferenceDate '2026-04-01' -WarningWindowDays 14
        $report.expired[0].name | Should -Be 'severe'
        $report.expired[1].name | Should -Be 'mild'
    }

    It 'throws when given no secrets' {
        { New-RotationReport -Secrets @() -ReferenceDate '2026-03-25' -WarningWindowDays 14 } |
            Should -Throw '*No secrets*'
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $script:secrets = @(
            [pscustomobject]@{ name = 'expired-1'; lastRotated = '2026-01-01'; rotationPolicyDays = 30;  requiredBy = @('api', 'cron') }
            [pscustomobject]@{ name = 'warning-1'; lastRotated = '2026-01-01'; rotationPolicyDays = 90;  requiredBy = @('worker') }
            [pscustomobject]@{ name = 'ok-1';      lastRotated = '2026-01-01'; rotationPolicyDays = 365; requiredBy = @('batch') }
        )
        $script:report = New-RotationReport -Secrets $script:secrets -ReferenceDate '2026-03-25' -WarningWindowDays 14
    }

    Context 'JSON format' {
        It 'produces valid JSON that round-trips to the same summary' {
            $json = Format-RotationReport -Report $script:report -Format json
            $parsed = $json | ConvertFrom-Json
            $parsed.summary.expired | Should -Be 1
            $parsed.expired[0].name | Should -Be 'expired-1'
        }
    }

    Context 'markdown format' {
        It 'renders a markdown table with a header row' {
            $md = Format-RotationReport -Report $script:report -Format markdown
            $md | Should -Match '# Secret Rotation Report'
            $md | Should -Match '\| Secret \| Status \| Last Rotated \| Due Date \| Days Until Due \| Required By \|'
        }

        It 'includes every secret name in the table' {
            $md = Format-RotationReport -Report $script:report -Format markdown
            $md | Should -Match 'expired-1'
            $md | Should -Match 'warning-1'
            $md | Should -Match 'ok-1'
        }

        It 'renders the requiredBy services comma-separated' {
            $md = Format-RotationReport -Report $script:report -Format markdown
            $md | Should -Match 'api, cron'
        }

        It 'shows summary counts grouped by urgency' {
            $md = Format-RotationReport -Report $script:report -Format markdown
            $md | Should -Match 'Expired:\*\* 1'
            $md | Should -Match 'Warning:\*\* 1'
            $md | Should -Match 'OK:\*\* 1'
        }
    }

    It 'throws on an unsupported format' {
        { Format-RotationReport -Report $script:report -Format xml } | Should -Throw '*Unsupported format*'
    }
}

Describe 'Import-SecretConfig' {

    It 'loads secrets from a JSON config file' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "secrets-$(New-Guid).json"
        @{
            secrets = @(
                @{ name = 'a'; lastRotated = '2026-01-01'; rotationPolicyDays = 30; requiredBy = @('api') }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp
        try {
            $secrets = Import-SecretConfig -Path $tmp
            $secrets[0].name | Should -Be 'a'
            $secrets[0].rotationPolicyDays | Should -Be 30
        }
        finally {
            Remove-Item $tmp -Force
        }
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path '/no/such/file.json' } | Should -Throw '*Config file not found*'
    }

    It 'throws a meaningful error when the JSON is malformed' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "bad-$(New-Guid).json"
        '{ not valid json' | Set-Content -Path $tmp
        try {
            { Import-SecretConfig -Path $tmp } | Should -Throw '*Failed to parse*'
        }
        finally {
            Remove-Item $tmp -Force
        }
    }

    It 'throws when the config has no secrets array' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "empty-$(New-Guid).json"
        '{ "other": 1 }' | Set-Content -Path $tmp
        try {
            { Import-SecretConfig -Path $tmp } | Should -Throw "*missing a 'secrets' array*"
        }
        finally {
            Remove-Item $tmp -Force
        }
    }
}
