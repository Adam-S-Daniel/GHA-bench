# Pester tests for the Secret Rotation Validator.
#
# TDD approach: each Describe block was written as a failing test first, then the
# minimum implementation in ../SecretRotation.ps1 was added to make it pass.
# The tests dot-source the *library* (SecretRotation.ps1) which only defines
# functions and produces no side effects on load, so it is safe to import here.

BeforeAll {
    # Resolve the library relative to this test file so it works from any CWD
    # (locally or inside the act container).
    $script:Root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:Root 'SecretRotation.ps1')

    $script:FixturesDir = Join-Path $PSScriptRoot 'fixtures'

    # A fixed "as of" date so every test is deterministic regardless of the
    # real wall-clock date in the CI container.
    $script:AsOf = [datetime]'2026-06-26'
}

Describe 'Read-SecretConfig' {
    It 'parses a valid config file into secret objects' {
        $secrets = Read-SecretConfig -Path (Join-Path $script:FixturesDir 'mixed.json')
        $secrets.Count | Should -Be 3
        $secrets[0].name | Should -Be 'expired-key'
        $secrets[0].rotationPolicyDays | Should -Be 90
        $secrets[0].requiredBy | Should -Contain 'payments-api'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Read-SecretConfig -Path (Join-Path $script:FixturesDir 'does-not-exist.json') } |
            Should -Throw -ExpectedMessage '*Config file not found*'
    }

    It 'throws a meaningful error on invalid JSON' {
        { Read-SecretConfig -Path (Join-Path $script:FixturesDir 'invalid-json.json') } |
            Should -Throw -ExpectedMessage '*not valid JSON*'
    }

    It 'throws when a secret is missing a required field' {
        { Read-SecretConfig -Path (Join-Path $script:FixturesDir 'missing-field.json') } |
            Should -Throw -ExpectedMessage "*missing required field 'rotationPolicyDays'*"
    }

    It 'throws when last-rotated is not a valid date' {
        { Read-SecretConfig -Path (Join-Path $script:FixturesDir 'bad-date.json') } |
            Should -Throw -ExpectedMessage '*invalid lastRotated date*'
    }

    It 'throws when rotationPolicyDays is not a positive integer' {
        { Read-SecretConfig -Path (Join-Path $script:FixturesDir 'bad-policy.json') } |
            Should -Throw -ExpectedMessage '*rotationPolicyDays must be a positive integer*'
    }
}

Describe 'Get-RotationStatus' {
    It 'flags an overdue secret as expired with negative daysUntilDue' {
        $secret = [pscustomobject]@{
            name = 'old'; lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('svc')
        }
        $r = Get-RotationStatus -Secret $secret -AsOf $script:AsOf -WarningWindowDays 7
        $r.status | Should -Be 'expired'
        $r.dueDate | Should -Be '2026-04-01'
        $r.daysUntilDue | Should -Be -86
    }

    It 'flags a soon-to-expire secret as warning' {
        $secret = [pscustomobject]@{
            name = 'soon'; lastRotated = '2026-04-01'; rotationPolicyDays = 90; requiredBy = @('svc')
        }
        $r = Get-RotationStatus -Secret $secret -AsOf $script:AsOf -WarningWindowDays 7
        $r.status | Should -Be 'warning'
        $r.dueDate | Should -Be '2026-06-30'
        $r.daysUntilDue | Should -Be 4
    }

    It 'flags a healthy secret as ok' {
        $secret = [pscustomobject]@{
            name = 'fresh'; lastRotated = '2026-06-01'; rotationPolicyDays = 90; requiredBy = @('svc')
        }
        $r = Get-RotationStatus -Secret $secret -AsOf $script:AsOf -WarningWindowDays 7
        $r.status | Should -Be 'ok'
        $r.daysUntilDue | Should -Be 65
    }

    It 'treats a secret due exactly on the warning-window edge as warning' {
        $secret = [pscustomobject]@{
            name = 'edge'; lastRotated = '2026-04-04'; rotationPolicyDays = 90; requiredBy = @('svc')
        }
        # due 2026-07-03 => 7 days out, window 7 => warning (inclusive edge)
        $r = Get-RotationStatus -Secret $secret -AsOf $script:AsOf -WarningWindowDays 7
        $r.daysUntilDue | Should -Be 7
        $r.status | Should -Be 'warning'
    }
}

Describe 'New-RotationReport' {
    BeforeAll {
        $secrets = Read-SecretConfig -Path (Join-Path $script:FixturesDir 'mixed.json')
        $script:Report = New-RotationReport -Secrets $secrets -AsOf $script:AsOf -WarningWindowDays 7
    }

    It 'groups secrets by urgency' {
        $script:Report.groups.expired.Count | Should -Be 1
        $script:Report.groups.warning.Count | Should -Be 1
        $script:Report.groups.ok.Count      | Should -Be 1
    }

    It 'produces an accurate summary' {
        $script:Report.summary.expired | Should -Be 1
        $script:Report.summary.warning | Should -Be 1
        $script:Report.summary.ok      | Should -Be 1
        $script:Report.summary.total   | Should -Be 3
    }

    It 'records the warning window and generation date' {
        $script:Report.warningWindowDays | Should -Be 7
        $script:Report.generatedAt       | Should -Be '2026-06-26'
    }
}

Describe 'Format-RotationReportJson' {
    It 'emits round-trippable JSON with the expected shape' {
        $secrets = Read-SecretConfig -Path (Join-Path $script:FixturesDir 'mixed.json')
        $report  = New-RotationReport -Secrets $secrets -AsOf $script:AsOf -WarningWindowDays 7
        $json    = Format-RotationReportJson -Report $report
        $parsed  = $json | ConvertFrom-Json
        $parsed.summary.total | Should -Be 3
        $parsed.groups.expired[0].name | Should -Be 'expired-key'
    }
}

Describe 'Format-RotationReportMarkdown' {
    It 'renders a markdown table with status sections' {
        $secrets = Read-SecretConfig -Path (Join-Path $script:FixturesDir 'mixed.json')
        $report  = New-RotationReport -Secrets $secrets -AsOf $script:AsOf -WarningWindowDays 7
        $md      = Format-RotationReportMarkdown -Report $report
        $md | Should -Match '# Secret Rotation Report'
        $md | Should -Match '\|\s*Secret\s*\|'          # table header
        $md | Should -Match 'expired-key'
        $md | Should -Match 'EXPIRED'
    }
}

Describe 'Invoke-SecretRotationValidator (end to end)' {
    It 'returns markdown by default' {
        $out = Invoke-SecretRotationValidator -Path (Join-Path $script:FixturesDir 'mixed.json') `
            -AsOf $script:AsOf -WarningWindowDays 7 -Format markdown
        $out | Should -Match '# Secret Rotation Report'
    }

    It 'returns JSON when requested' {
        $out = Invoke-SecretRotationValidator -Path (Join-Path $script:FixturesDir 'mixed.json') `
            -AsOf $script:AsOf -WarningWindowDays 7 -Format json
        ($out | ConvertFrom-Json).summary.total | Should -Be 3
    }

    It 'rejects an unknown format' {
        { Invoke-SecretRotationValidator -Path (Join-Path $script:FixturesDir 'mixed.json') `
            -AsOf $script:AsOf -WarningWindowDays 7 -Format xml } |
            Should -Throw -ExpectedMessage '*Unsupported format*'
    }
}
