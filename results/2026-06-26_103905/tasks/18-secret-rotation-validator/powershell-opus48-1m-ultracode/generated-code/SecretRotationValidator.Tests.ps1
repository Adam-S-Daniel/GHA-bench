# SecretRotationValidator.Tests.ps1
#
# Pester (v5) unit tests for the Secret Rotation Validator.
#
# TDD approach: each Describe block was written test-first (red), then the
# minimum production code was added to SecretRotationValidator.ps1 to make it
# pass (green), then refactored. The tests dot-source the script under test so
# that all of its functions become available without executing the CLI entry
# point (that entry point is guarded so it only runs when the script is invoked
# directly, not when dot-sourced).

BeforeAll {
    . $PSScriptRoot/SecretRotationValidator.ps1

    # Declarative secret builder. Defined in BeforeAll so it is available inside
    # It blocks at run time (Pester v5 discovery/run scope separation).
    function New-Secret {
        param(
            $Name = 'DB_PASSWORD',
            $LastRotated = '2026-01-01',
            $PolicyDays = 90,
            $RequiredBy = @('api')
        )
        [pscustomobject]@{
            name               = $Name
            lastRotated        = $LastRotated
            rotationPolicyDays = $PolicyDays
            requiredBy         = $RequiredBy
        }
    }

    # Fixed "now" so every date assertion is deterministic.
    $script:Ref = [datetime]'2026-06-28'
}

Describe 'Get-SecretRotationStatus' {

    Context 'classification' {

        It 'marks a secret past its rotation policy as expired' {
            # Rotated 2026-01-01, policy 90 days => expires 2026-04-01, long past 2026-06-28.
            $status = Get-SecretRotationStatus -Secret (New-Secret) -ReferenceDate $Ref -WarningWindowDays 14
            $status.Status | Should -Be 'expired'
        }

        It 'marks a secret expiring inside the warning window as warning' {
            # Rotated 2026-04-01, policy 90 days => expires 2026-06-30, i.e. 2 days out.
            $secret = New-Secret -LastRotated '2026-04-01' -PolicyDays 90
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 14
            $status.Status | Should -Be 'warning'
        }

        It 'marks a comfortably-in-policy secret as ok' {
            # Rotated 2026-06-01, policy 90 days => expires 2026-08-30, 63 days out.
            $secret = New-Secret -LastRotated '2026-06-01' -PolicyDays 90
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 14
            $status.Status | Should -Be 'ok'
        }

        It 'treats a secret expiring exactly today as warning, not expired' {
            # Rotated 2026-03-30, policy 90 days => expires 2026-06-28 == reference date.
            $secret = New-Secret -LastRotated '2026-03-30' -PolicyDays 90
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 14
            $status.Status          | Should -Be 'warning'
            $status.DaysUntilExpiry | Should -Be 0
        }

        It 'respects a wider warning window' {
            # 63 days out is 'ok' at window=14 but 'warning' at window=90.
            $secret = New-Secret -LastRotated '2026-06-01' -PolicyDays 90
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 90
            $status.Status | Should -Be 'warning'
        }
    }

    Context 'computed fields' {

        It 'computes expiry date, days-until-expiry and days-since-rotation' {
            $secret = New-Secret -LastRotated '2026-04-01' -PolicyDays 90
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 14
            $status.ExpiryDate        | Should -Be ([datetime]'2026-06-30')
            $status.DaysUntilExpiry   | Should -Be 2
            $status.DaysSinceRotation | Should -Be 88
            $status.RotationPolicyDays | Should -Be 90
        }

        It 'carries through name and required-by services' {
            $secret = New-Secret -Name 'API_TOKEN' -RequiredBy @('web', 'worker')
            $status = Get-SecretRotationStatus -Secret $secret -ReferenceDate $Ref -WarningWindowDays 14
            $status.Name       | Should -Be 'API_TOKEN'
            $status.RequiredBy | Should -Be @('web', 'worker')
        }
    }
}

Describe 'Import-SecretConfig' {

    BeforeAll {
        # Helper to drop a config file into Pester's auto-cleaned TestDrive.
        function Set-ConfigFile {
            param([string]$Name = 'config.json', [string]$Content)
            $path = Join-Path $TestDrive $Name
            Set-Content -LiteralPath $path -Value $Content -Encoding utf8
            $path
        }
    }

    Context 'valid configuration' {

        It 'parses the secrets array' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "name": "A", "lastRotated": "2026-01-01", "rotationPolicyDays": 90, "requiredBy": ["api"] } ] }'
            $config = Import-SecretConfig -Path $path
            $config.Secrets.Count       | Should -Be 1
            $config.Secrets[0].name     | Should -Be 'A'
        }

        It 'surfaces optional referenceDate and warningWindowDays' {
            $path = Set-ConfigFile -Content '{ "referenceDate": "2026-06-28", "warningWindowDays": 30, "secrets": [ { "name": "A", "lastRotated": "2026-01-01", "rotationPolicyDays": 90 } ] }'
            $config = Import-SecretConfig -Path $path
            $config.ReferenceDate     | Should -Be ([datetime]'2026-06-28')
            $config.WarningWindowDays | Should -Be 30
        }

        It 'leaves referenceDate and warningWindowDays null when omitted' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "name": "A", "lastRotated": "2026-01-01", "rotationPolicyDays": 90 } ] }'
            $config = Import-SecretConfig -Path $path
            $config.ReferenceDate     | Should -BeNullOrEmpty
            $config.WarningWindowDays | Should -BeNullOrEmpty
        }
    }

    Context 'error handling' {

        It 'throws a clear error when the file is missing' {
            { Import-SecretConfig -Path (Join-Path $TestDrive 'nope.json') } |
                Should -Throw '*not found*'
        }

        It 'throws a clear error on malformed JSON' {
            $path = Set-ConfigFile -Content '{ this is not json'
            { Import-SecretConfig -Path $path } | Should -Throw '*Invalid JSON*'
        }

        It 'throws when the secrets array is absent' {
            $path = Set-ConfigFile -Content '{ "warningWindowDays": 14 }'
            { Import-SecretConfig -Path $path } | Should -Throw "*'secrets'*"
        }

        It 'throws when a secret is missing its name' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "lastRotated": "2026-01-01", "rotationPolicyDays": 90 } ] }'
            { Import-SecretConfig -Path $path } | Should -Throw '*name*'
        }

        It 'throws when a secret is missing lastRotated, naming the offending secret' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "name": "DB", "rotationPolicyDays": 90 } ] }'
            { Import-SecretConfig -Path $path } | Should -Throw "*DB*lastRotated*"
        }

        It 'throws when lastRotated is not a parseable date' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "name": "DB", "lastRotated": "not-a-date", "rotationPolicyDays": 90 } ] }'
            { Import-SecretConfig -Path $path } | Should -Throw "*DB*lastRotated*"
        }

        It 'throws when rotationPolicyDays is not a positive integer' {
            $path = Set-ConfigFile -Content '{ "secrets": [ { "name": "DB", "lastRotated": "2026-01-01", "rotationPolicyDays": 0 } ] }'
            { Import-SecretConfig -Path $path } | Should -Throw "*DB*rotationPolicyDays*"
        }
    }
}

Describe 'Get-RotationReport' {

    BeforeAll {
        # A mixed portfolio: two expired (differing overdue amounts), one warning,
        # one ok — exercises categorisation, counts and within-group ordering.
        $script:MixedSecrets = @(
            (New-Secret -Name 'EXPIRED_MILD'   -LastRotated '2026-01-01' -PolicyDays 90)  # expiry 2026-04-01 => -88
            (New-Secret -Name 'EXPIRED_SEVERE' -LastRotated '2026-01-01' -PolicyDays 30)  # expiry 2026-01-31 => -148
            (New-Secret -Name 'WARN_SOON'      -LastRotated '2026-04-01' -PolicyDays 90)  # expiry 2026-06-30 => +2
            (New-Secret -Name 'ALL_GOOD'       -LastRotated '2026-06-01' -PolicyDays 90)  # expiry 2026-08-30 => +63
        )
    }

    It 'produces accurate summary counts per urgency' {
        $report = Get-RotationReport -Secrets $MixedSecrets -ReferenceDate $Ref -WarningWindowDays 14
        $report.Summary.Expired | Should -Be 2
        $report.Summary.Warning | Should -Be 1
        $report.Summary.Ok      | Should -Be 1
        $report.Summary.Total   | Should -Be 4
    }

    It 'echoes the evaluation parameters used' {
        $report = Get-RotationReport -Secrets $MixedSecrets -ReferenceDate $Ref -WarningWindowDays 14
        $report.ReferenceDate     | Should -Be $Ref
        $report.WarningWindowDays | Should -Be 14
    }

    It 'groups secrets by urgency in expired -> warning -> ok order' {
        $report = Get-RotationReport -Secrets $MixedSecrets -ReferenceDate $Ref -WarningWindowDays 14
        $report.Groups.Status | Should -Be @('expired', 'warning', 'ok')
    }

    It 'orders the expired group most-overdue first' {
        $report = Get-RotationReport -Secrets $MixedSecrets -ReferenceDate $Ref -WarningWindowDays 14
        $expired = ($report.Groups | Where-Object Status -eq 'expired').Secrets
        $expired.Name | Should -Be @('EXPIRED_SEVERE', 'EXPIRED_MILD')
    }

    It 'returns zeroed counts and empty groups for an empty portfolio' {
        $report = Get-RotationReport -Secrets @() -ReferenceDate $Ref -WarningWindowDays 14
        $report.Summary.Total   | Should -Be 0
        $report.Summary.Expired | Should -Be 0
        $report.Groups.Count    | Should -Be 3
        ($report.Groups | Where-Object Status -eq 'expired').Secrets.Count | Should -Be 0
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $script:Secrets = @(
            (New-Secret -Name 'EXPIRED_MILD'   -LastRotated '2026-01-01' -PolicyDays 90)
            (New-Secret -Name 'EXPIRED_SEVERE' -LastRotated '2026-01-01' -PolicyDays 30)
            (New-Secret -Name 'WARN_SOON'      -LastRotated '2026-04-01' -PolicyDays 90 -RequiredBy @('web', 'worker'))
            (New-Secret -Name 'ALL_GOOD'       -LastRotated '2026-06-01' -PolicyDays 90)
        )
        $script:Report = Get-RotationReport -Secrets $Secrets -ReferenceDate $Ref -WarningWindowDays 14
    }

    Context 'markdown format' {

        It 'renders a titled report with per-urgency sections and a summary line' {
            $md = Format-RotationReport -Report $Report -Format markdown
            $md | Should -BeLike '*# Secret Rotation Report*'
            $md | Should -BeLike '*## Expired (2)*'
            $md | Should -BeLike '*## Warning (1)*'
            $md | Should -BeLike '*## OK (1)*'
            $md | Should -BeLike '*2 expired, 1 warning, 1 ok*'
        }

        It 'renders a Markdown table with the secret names and required-by services' {
            $md = Format-RotationReport -Report $Report -Format markdown
            $md | Should -Match '\|\s*---'         # a table separator row exists
            $md | Should -BeLike '*EXPIRED_SEVERE*'
            $md | Should -BeLike '*web, worker*'    # requiredBy joined
        }

        It 'lists the most overdue expired secret first' {
            $md = Format-RotationReport -Report $Report -Format markdown
            $idxSevere = $md.IndexOf('EXPIRED_SEVERE')
            $idxMild   = $md.IndexOf('EXPIRED_MILD')
            $idxSevere | Should -BeLessThan $idxMild
        }

        It 'shows a placeholder for an empty urgency group' {
            $empty = Get-RotationReport -Secrets @() -ReferenceDate $Ref -WarningWindowDays 14
            $md = Format-RotationReport -Report $empty -Format markdown
            $md | Should -BeLike '*_None_*'
        }

        It 'is the default format' {
            $default = Format-RotationReport -Report $Report
            $default | Should -BeLike '*# Secret Rotation Report*'
        }
    }

    Context 'json format' {

        It 'emits valid JSON that round-trips to the same summary counts' {
            $json = Format-RotationReport -Report $Report -Format json
            $obj  = $json | ConvertFrom-Json
            $obj.summary.expired | Should -Be 2
            $obj.summary.warning | Should -Be 1
            $obj.summary.ok      | Should -Be 1
            $obj.summary.total   | Should -Be 4
        }

        It 'serialises evaluation metadata and per-secret detail' {
            $obj = (Format-RotationReport -Report $Report -Format json) | ConvertFrom-Json
            $obj.referenceDate     | Should -Be '2026-06-28'
            $obj.warningWindowDays | Should -Be 14
            ($obj.secrets | Where-Object name -eq 'WARN_SOON').status          | Should -Be 'warning'
            ($obj.secrets | Where-Object name -eq 'WARN_SOON').daysUntilExpiry | Should -Be 2
            ($obj.secrets | Where-Object name -eq 'WARN_SOON').expiryDate      | Should -Be '2026-06-30'
        }
    }
}

Describe 'Get-RotationSummaryMarkers' {
    # These single-line markers are what CI greps for, so they must be stable
    # and — critically — StrictMode-safe even when an urgency group is empty.
    BeforeAll {
        $script:Secrets = @(
            (New-Secret -Name 'EXPIRED_MILD'   -LastRotated '2026-01-01' -PolicyDays 90)
            (New-Secret -Name 'EXPIRED_SEVERE' -LastRotated '2026-01-01' -PolicyDays 30)
            (New-Secret -Name 'WARN_SOON'      -LastRotated '2026-04-01' -PolicyDays 90)
        )
    }

    It 'emits a ROTATION_SUMMARY line and per-group membership in urgency order' {
        $report  = Get-RotationReport -Secrets $Secrets -ReferenceDate $Ref -WarningWindowDays 14
        $markers = Get-RotationSummaryMarkers -Report $report
        $markers | Should -BeLike '*ROTATION_SUMMARY expired=2 warning=1 ok=0 total=3*'
        $markers | Should -BeLike '*GROUP EXPIRED: EXPIRED_SEVERE,EXPIRED_MILD*'
        $markers | Should -BeLike '*GROUP WARNING: WARN_SOON*'
    }

    It 'handles empty groups without throwing under StrictMode' {
        $report  = Get-RotationReport -Secrets @() -ReferenceDate $Ref -WarningWindowDays 14
        { Get-RotationSummaryMarkers -Report $report } | Should -Not -Throw
        $markers = Get-RotationSummaryMarkers -Report $report
        $markers | Should -BeLike '*ROTATION_SUMMARY expired=0 warning=0 ok=0 total=0*'
        $markers | Should -BeLike '*GROUP EXPIRED: *'   # present, with empty membership
    }
}

Describe 'Invoke-SecretRotationValidator' {

    BeforeAll {
        function Set-ConfigFile {
            param([string]$Name = 'config.json', [string]$Content)
            $path = Join-Path $TestDrive $Name
            Set-Content -LiteralPath $path -Value $Content -Encoding utf8
            $path
        }

        # Mixed config WITH self-contained referenceDate + warningWindowDays so
        # the orchestrator's defaults are deterministic.
        $script:MixedPath = Set-ConfigFile -Name 'mixed.json' -Content @'
{
  "referenceDate": "2026-06-28",
  "warningWindowDays": 14,
  "secrets": [
    { "name": "EXP",  "lastRotated": "2026-01-01", "rotationPolicyDays": 90, "requiredBy": ["api"] },
    { "name": "OKAY", "lastRotated": "2026-06-01", "rotationPolicyDays": 90, "requiredBy": ["web"] }
  ]
}
'@
    }

    Context 'parameter precedence' {

        It 'uses the config file referenceDate and warningWindowDays by default' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath
            $r.ReferenceDate     | Should -Be ([datetime]'2026-06-28')
            $r.WarningWindowDays | Should -Be 14
            $r.Report.Summary.Expired | Should -Be 1
            $r.Report.Summary.Ok      | Should -Be 1
        }

        It 'lets an explicit -WarningWindowDays override the config value' {
            # 63-days-out OKAY becomes a 'warning' once the window widens to 90.
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath -WarningWindowDays 90
            $r.WarningWindowDays      | Should -Be 90
            $r.Report.Summary.Warning | Should -Be 1
            $r.Report.Summary.Ok      | Should -Be 0
        }

        It 'lets an explicit -ReferenceDate override the config value' {
            # Evaluated at 2026-03-01, EXP (expires 2026-04-01) is no longer expired.
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath -ReferenceDate ([datetime]'2026-03-01')
            $r.ReferenceDate          | Should -Be ([datetime]'2026-03-01')
            $r.Report.Summary.Expired | Should -Be 0
        }

        It 'defaults the warning window to 14 and reference date to today when neither config nor param supplies them' {
            $path = Set-ConfigFile -Name 'bare.json' -Content '{ "secrets": [ { "name": "A", "lastRotated": "2026-01-01", "rotationPolicyDays": 90 } ] }'
            $r = Invoke-SecretRotationValidator -ConfigPath $path
            $r.WarningWindowDays    | Should -Be 14
            $r.ReferenceDate.Date   | Should -Be (Get-Date).Date
        }
    }

    Context 'output' {

        It 'renders markdown by default' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath
            $r.Output | Should -BeLike '*# Secret Rotation Report*'
        }

        It 'renders JSON on request' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath -Format json
            ($r.Output | ConvertFrom-Json).summary.expired | Should -Be 1
        }

        It 'writes the rendered report to -OutputPath when provided' {
            $out = Join-Path $TestDrive 'report.md'
            Invoke-SecretRotationValidator -ConfigPath $MixedPath -OutputPath $out | Out-Null
            Test-Path $out                    | Should -BeTrue
            (Get-Content $out -Raw)           | Should -BeLike '*# Secret Rotation Report*'
        }
    }

    Context 'exit-code policy (CI guardrail)' {

        It 'flags HasExpired but exits 0 by default even with expired secrets' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath
            $r.HasExpired | Should -BeTrue
            $r.ExitCode   | Should -Be 0
        }

        It 'exits non-zero with -FailOnExpired when a secret is expired' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath -FailOnExpired
            $r.ExitCode | Should -Be 1
        }

        It 'exits 0 with -FailOnExpired when nothing is expired' {
            $r = Invoke-SecretRotationValidator -ConfigPath $MixedPath -ReferenceDate ([datetime]'2026-03-01') -FailOnExpired
            $r.ExitCode | Should -Be 0
        }
    }

    Context 'error handling' {

        It 'propagates a clear error when the config file is missing' {
            { Invoke-SecretRotationValidator -ConfigPath (Join-Path $TestDrive 'ghost.json') } |
                Should -Throw '*not found*'
        }
    }
}
