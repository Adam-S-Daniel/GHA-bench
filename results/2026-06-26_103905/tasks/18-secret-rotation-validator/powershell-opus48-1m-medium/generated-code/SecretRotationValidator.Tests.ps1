#requires -Modules Pester

# Unit tests for the Secret Rotation Validator.
#
# Developed red/green/refactor: each Describe block was written as a failing
# test first, then the minimum implementation was added to SecretRotationValidator.ps1
# to make it pass. The tests are deliberately deterministic — every test pins a
# fixed -ReferenceDate so "now" never drifts and assertions stay exact.

BeforeAll {
    # Dot-source the implementation under test. The script is written so that
    # dot-sourcing only defines functions (the main entry point is guarded), which
    # makes every function independently testable.
    . "$PSScriptRoot/SecretRotationValidator.ps1"

    # A small, fully-known set of mock secrets used across tests. All dates are
    # chosen relative to the fixed reference date 2026-06-26 so the resulting
    # status (Expired / Warning / Ok) is unambiguous.
    $script:RefDate = [datetime]'2026-06-26'
    $script:MockSecrets = @(
        # Expired: rotated 2026-01-01, 90-day policy => expires 2026-04-01 (-86 days)
        [pscustomobject]@{ Name = 'db-password';  LastRotated = '2026-01-01'; RotationPolicyDays = 90; RequiredBy = @('api', 'worker') }
        # Warning: rotated 2026-04-01, 90-day policy => expires 2026-06-30 (+4 days)
        [pscustomobject]@{ Name = 'api-key';       LastRotated = '2026-04-01'; RotationPolicyDays = 90; RequiredBy = @('gateway') }
        # Ok: rotated 2026-06-01, 90-day policy => expires 2026-08-30 (+65 days)
        [pscustomobject]@{ Name = 'tls-cert';      LastRotated = '2026-06-01'; RotationPolicyDays = 90; RequiredBy = @('web') }
    )
}

Describe 'Get-SecretRotationStatus' {

    It 'classifies a secret past its policy window as Expired' {
        $result = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 7 -ReferenceDate $script:RefDate
        $db = $result | Where-Object Name -EQ 'db-password'
        $db.Status | Should -Be 'Expired'
        $db.DaysUntilExpiry | Should -Be -86
        $db.ExpiryDate | Should -Be ([datetime]'2026-04-01')
    }

    It 'classifies a secret inside the warning window as Warning' {
        $result = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 7 -ReferenceDate $script:RefDate
        $api = $result | Where-Object Name -EQ 'api-key'
        $api.Status | Should -Be 'Warning'
        $api.DaysUntilExpiry | Should -Be 4
    }

    It 'classifies a secret well within policy as Ok' {
        $result = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 7 -ReferenceDate $script:RefDate
        $tls = $result | Where-Object Name -EQ 'tls-cert'
        $tls.Status | Should -Be 'Ok'
        $tls.DaysUntilExpiry | Should -Be 65
    }

    It 'treats the warning window boundary as inclusive' {
        # Expires exactly WarningDays away => still Warning, not Ok.
        $boundary = @([pscustomobject]@{ Name = 'edge'; LastRotated = '2026-06-19'; RotationPolicyDays = 14; RequiredBy = @('svc') })
        $result = Get-SecretRotationStatus -Secrets $boundary -WarningDays 7 -ReferenceDate $script:RefDate
        # expires 2026-07-03 => +7 days
        $result.DaysUntilExpiry | Should -Be 7
        $result.Status | Should -Be 'Warning'
    }

    It 'honours a configurable warning window' {
        # With a 0-day window the +4-day api-key is no longer a warning, it is Ok.
        $result = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 0 -ReferenceDate $script:RefDate
        ($result | Where-Object Name -EQ 'api-key').Status | Should -Be 'Ok'
    }

    It 'throws a meaningful error on a non-positive rotation policy' {
        $bad = @([pscustomobject]@{ Name = 'oops'; LastRotated = '2026-01-01'; RotationPolicyDays = 0; RequiredBy = @('x') })
        { Get-SecretRotationStatus -Secrets $bad -ReferenceDate $script:RefDate } |
            Should -Throw -ExpectedMessage "*oops*RotationPolicyDays*"
    }

    It 'throws a meaningful error on an unparseable last-rotated date' {
        $bad = @([pscustomobject]@{ Name = 'oops'; LastRotated = 'not-a-date'; RotationPolicyDays = 30; RequiredBy = @('x') })
        { Get-SecretRotationStatus -Secrets $bad -ReferenceDate $script:RefDate } |
            Should -Throw -ExpectedMessage "*oops*LastRotated*"
    }
}

Describe 'ConvertFrom-SecretConfig' {

    It 'reads and parses a JSON config file into secret objects' {
        $tmp = Join-Path $TestDrive 'secrets.json'
        $json = @{
            secrets = @(
                @{ name = 'db-password'; lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('api') }
            )
        } | ConvertTo-Json -Depth 5
        Set-Content -Path $tmp -Value $json -Encoding utf8

        $secrets = ConvertFrom-SecretConfig -Path $tmp
        $secrets | Should -HaveCount 1
        $secrets[0].Name | Should -Be 'db-password'
        $secrets[0].RotationPolicyDays | Should -Be 90
        $secrets[0].RequiredBy | Should -Be @('api')
    }

    It 'throws a meaningful error when the file does not exist' {
        { ConvertFrom-SecretConfig -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw -ExpectedMessage "*not found*"
    }

    It 'throws a meaningful error on malformed JSON' {
        $tmp = Join-Path $TestDrive 'broken.json'
        Set-Content -Path $tmp -Value '{ this is not json' -Encoding utf8
        { ConvertFrom-SecretConfig -Path $tmp } | Should -Throw -ExpectedMessage "*Failed to parse*"
    }

    It 'throws when a required field is missing' {
        $tmp = Join-Path $TestDrive 'incomplete.json'
        (@{ secrets = @(@{ name = 'x' }) } | ConvertTo-Json -Depth 5) | Set-Content -Path $tmp -Encoding utf8
        { ConvertFrom-SecretConfig -Path $tmp } | Should -Throw -ExpectedMessage "*missing*"
    }
}

Describe 'New-RotationReport' {

    It 'groups secrets by urgency with summary counts' {
        $statuses = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 7 -ReferenceDate $script:RefDate
        $report = New-RotationReport -Statuses $statuses -ReferenceDate $script:RefDate -WarningDays 7

        $report.Summary.Expired | Should -Be 1
        $report.Summary.Warning | Should -Be 1
        $report.Summary.Ok | Should -Be 1
        $report.Summary.Total | Should -Be 3
        $report.Expired[0].Name | Should -Be 'db-password'
        $report.Warning[0].Name | Should -Be 'api-key'
        $report.Ok[0].Name | Should -Be 'tls-cert'
        $report.ReferenceDate | Should -Be '2026-06-26'
        $report.WarningDays | Should -Be 7
    }

    It 'produces zeroed summary for an empty secret set' {
        $report = New-RotationReport -Statuses @() -ReferenceDate $script:RefDate -WarningDays 7
        $report.Summary.Total | Should -Be 0
        $report.Summary.Expired | Should -Be 0
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $statuses = Get-SecretRotationStatus -Secrets $script:MockSecrets -WarningDays 7 -ReferenceDate $script:RefDate
        $script:Report = New-RotationReport -Statuses $statuses -ReferenceDate $script:RefDate -WarningDays 7
    }

    It 'renders a markdown report with a summary and per-urgency tables' {
        $md = Format-RotationReport -Report $script:Report -Format Markdown
        $md | Should -Match '# Secret Rotation Report'
        $md | Should -Match 'Expired: 1'
        $md | Should -Match 'Warning: 1'
        $md | Should -Match 'Ok: 1'
    }

    It 'renders the expired secret name inside the markdown table' {
        $md = Format-RotationReport -Report $script:Report -Format Markdown
        $md | Should -Match 'db-password'
        $md | Should -Match 'api, worker'   # required-by list joined
    }

    It 'renders valid JSON that round-trips to the same summary counts' {
        $json = Format-RotationReport -Report $script:Report -Format Json
        $parsed = $json | ConvertFrom-Json
        $parsed.Summary.Expired | Should -Be 1
        $parsed.Summary.Warning | Should -Be 1
        $parsed.Summary.Ok | Should -Be 1
        $parsed.Expired[0].Name | Should -Be 'db-password'
    }

    It 'rejects an unsupported format' {
        { Format-RotationReport -Report $script:Report -Format Xml } | Should -Throw
    }
}
