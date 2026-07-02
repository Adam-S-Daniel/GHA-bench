<#
.SYNOPSIS
    Pester tests for the SecretRotationValidator module.

.DESCRIPTION
    Built with red/green TDD. Each Describe block corresponds to one TDD cycle:
      1. Get-SecretRotationStatus  - classify a single secret (first failing test)
      2. Import-SecretConfig       - load + validate the secrets config file
      3. Get-RotationReport        - build the full report grouped by urgency
      4. Format-RotationReport     - render markdown / JSON output

    All date math is done against an injectable -AsOfDate so tests are
    deterministic (no reliance on the wall clock).
#>

BeforeAll {
    # Import the module under test fresh each run.
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'SecretRotationValidator.psm1') -Force

    # A fixed "today" used by every test for deterministic date math.
    $script:AsOf = [datetime]::ParseExact('2026-01-15', 'yyyy-MM-dd', $null)
}

Describe 'Get-SecretRotationStatus' {
    # TDD cycle 1: the core classification rule.
    #   expiry = lastRotated + rotationPolicyDays
    #   DaysUntilExpiry < 0            -> Expired
    #   0 <= DaysUntilExpiry <= window -> Warning
    #   otherwise                      -> OK

    It 'classifies a secret past its rotation policy as Expired' {
        $secret = [pscustomobject]@{
            Name               = 'db-password'
            LastRotated        = '2025-10-01'   # + 90 days = 2025-12-30, 16 days overdue
            RotationPolicyDays = 90
            RequiredBy         = @('billing-api')
        }
        $result = Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14
        $result.Status          | Should -Be 'Expired'
        $result.DaysUntilExpiry | Should -Be -16
        $result.ExpiresOn       | Should -Be '2025-12-30'
    }

    It 'classifies a secret expiring inside the warning window as Warning' {
        $secret = [pscustomobject]@{
            Name               = 'api-key'
            LastRotated        = '2025-10-20'   # + 90 days = 2026-01-18, 3 days left
            RotationPolicyDays = 90
            RequiredBy         = @('web-frontend', 'mobile-app')
        }
        $result = Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14
        $result.Status          | Should -Be 'Warning'
        $result.DaysUntilExpiry | Should -Be 3
    }

    It 'classifies a secret outside the warning window as OK' {
        $secret = [pscustomobject]@{
            Name               = 'tls-cert'
            LastRotated        = '2026-01-01'   # + 365 days = 2027-01-01
            RotationPolicyDays = 365
            RequiredBy         = @('ingress')
        }
        $result = Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14
        $result.Status          | Should -Be 'OK'
        $result.DaysUntilExpiry | Should -Be 351
    }

    It 'treats a secret expiring exactly today as Warning (still usable, rotate now)' {
        $secret = [pscustomobject]@{
            Name               = 'edge-case'
            LastRotated        = '2025-12-16'   # + 30 days = 2026-01-15 = AsOf
            RotationPolicyDays = 30
            RequiredBy         = @()
        }
        $result = Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14
        $result.Status          | Should -Be 'Warning'
        $result.DaysUntilExpiry | Should -Be 0
    }

    It 'throws a meaningful error for an unparseable LastRotated date' {
        $secret = [pscustomobject]@{
            Name               = 'broken'
            LastRotated        = 'not-a-date'
            RotationPolicyDays = 30
            RequiredBy         = @()
        }
        { Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14 } |
            Should -Throw "*Secret 'broken'*invalid LastRotated date*"
    }

    It 'throws a meaningful error for a non-positive rotation policy' {
        $secret = [pscustomobject]@{
            Name               = 'zero-policy'
            LastRotated        = '2026-01-01'
            RotationPolicyDays = 0
            RequiredBy         = @()
        }
        { Get-SecretRotationStatus -Secret $secret -AsOfDate $AsOf -WarningWindowDays 14 } |
            Should -Throw "*Secret 'zero-policy'*RotationPolicyDays must be a positive integer*"
    }
}

Describe 'Import-SecretConfig' {
    # TDD cycle 2: load the secrets config JSON, validate its shape, and
    # normalize property names to the PascalCase the rest of the module uses.

    BeforeAll {
        $script:FixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json'
    }

    It 'loads a valid config file and normalizes secret properties' {
        $config = Import-SecretConfig -Path $FixturePath
        $config.WarningWindowDays | Should -Be 14
        $config.Secrets           | Should -HaveCount 4
        $config.Secrets[0].Name               | Should -Be 'db-password'
        $config.Secrets[0].LastRotated        | Should -Be '2025-10-01'
        $config.Secrets[0].RotationPolicyDays | Should -Be 90
        $config.Secrets[0].RequiredBy         | Should -Be @('billing-api', 'reporting-service')
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw '*Config file not found*missing.json*'
    }

    It 'throws a meaningful error for malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{ this is not json'
        { Import-SecretConfig -Path $bad } |
            Should -Throw '*not valid JSON*'
    }

    It 'throws a meaningful error when the secrets array is missing' {
        $noSecrets = Join-Path $TestDrive 'nosecrets.json'
        Set-Content -Path $noSecrets -Value '{ "warningWindowDays": 7 }'
        { Import-SecretConfig -Path $noSecrets } |
            Should -Throw "*must contain a non-empty 'secrets' array*"
    }

    It 'throws a meaningful error when a secret is missing a required field' {
        $missingField = Join-Path $TestDrive 'missingfield.json'
        Set-Content -Path $missingField -Value '{ "secrets": [ { "name": "orphan", "rotationPolicyDays": 30 } ] }'
        { Import-SecretConfig -Path $missingField } |
            Should -Throw "*Secret 'orphan'*missing required field 'lastRotated'*"
    }

    It 'defaults warningWindowDays to 14 when not specified in the config' {
        $noWindow = Join-Path $TestDrive 'nowindow.json'
        Set-Content -Path $noWindow -Value '{ "secrets": [ { "name": "s1", "lastRotated": "2026-01-01", "rotationPolicyDays": 30, "requiredBy": [] } ] }'
        (Import-SecretConfig -Path $noWindow).WarningWindowDays | Should -Be 14
    }
}

Describe 'Get-RotationReport' {
    # TDD cycle 3: evaluate every secret in a config and group the results
    # by urgency: Expired first, then Warning, then OK. Within each group,
    # secrets sort by soonest expiry so the most urgent item is always first.

    BeforeAll {
        $script:Report = Get-RotationReport `
            -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json') `
            -AsOfDate $AsOf
    }

    It 'groups secrets into Expired / Warning / OK buckets' {
        $Report.Expired.Name | Should -Be @('signing-key', 'db-password')  # -18 then -16 days
        $Report.Warning.Name | Should -Be @('api-key')
        $Report.Ok.Name      | Should -Be @('tls-cert')
    }

    It 'carries summary counts and metadata for downstream formatting' {
        $Report.Summary.Total      | Should -Be 4
        $Report.Summary.Expired    | Should -Be 2
        $Report.Summary.Warning    | Should -Be 1
        $Report.Summary.Ok         | Should -Be 1
        $Report.AsOfDate           | Should -Be '2026-01-15'
        $Report.WarningWindowDays  | Should -Be 14
    }

    It 'lets an explicit -WarningWindowDays override the config value' {
        # Window of 0: only already-expired secrets or same-day expiries warn.
        $override = Get-RotationReport `
            -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json') `
            -AsOfDate $AsOf -WarningWindowDays 0
        $override.Warning | Should -HaveCount 0
        $override.Ok.Name | Should -Be @('api-key', 'tls-cert')
    }
}

Describe 'Format-RotationReport' {
    # TDD cycle 4: render the report as a markdown table or JSON. These are
    # the notification payloads, grouped by urgency (expired, warning, ok).

    BeforeAll {
        $script:Report = Get-RotationReport `
            -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json') `
            -AsOfDate $AsOf
    }

    Context 'Markdown format' {
        BeforeAll {
            $script:Markdown = Format-RotationReport -Report $Report -Format Markdown
        }

        It 'renders a header with the as-of date and summary counts' {
            $Markdown | Should -Match ([regex]::Escape('# Secret Rotation Report'))
            $Markdown | Should -Match ([regex]::Escape('**As of:** 2026-01-15 | **Warning window:** 14 days'))
            $Markdown | Should -Match ([regex]::Escape('**Totals:** 4 secrets — 2 expired, 1 warning, 1 ok'))
        }

        It 'renders one section per urgency group with counts' {
            $Markdown | Should -Match ([regex]::Escape('## EXPIRED (2) — rotate immediately'))
            $Markdown | Should -Match ([regex]::Escape('## WARNING (1) — rotate soon'))
            $Markdown | Should -Match ([regex]::Escape('## OK (1)'))
        }

        It 'renders exact table rows, most urgent first' {
            $Markdown | Should -Match ([regex]::Escape('| signing-key | 2025-12-28 | -18 | 2025-07-01 | 180 | auth-service |'))
            $Markdown | Should -Match ([regex]::Escape('| db-password | 2025-12-30 | -16 | 2025-10-01 | 90 | billing-api, reporting-service |'))
            $Markdown | Should -Match ([regex]::Escape('| api-key | 2026-01-18 | 3 | 2025-10-20 | 90 | web-frontend, mobile-app |'))
            $Markdown | Should -Match ([regex]::Escape('| tls-cert | 2027-01-01 | 351 | 2026-01-01 | 365 | ingress |'))
        }

        It 'says so instead of rendering an empty table when a group is empty' {
            $emptyGroups = Get-RotationReport `
                -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json') `
                -AsOfDate ([datetime]::ParseExact('2025-10-25', 'yyyy-MM-dd', $null))
            $md = Format-RotationReport -Report $emptyGroups -Format Markdown
            $md | Should -Match ([regex]::Escape('## EXPIRED (0) — rotate immediately'))
            $md | Should -Match ([regex]::Escape('_No secrets in this group._'))
        }
    }

    Context 'JSON format' {
        BeforeAll {
            $script:Json   = Format-RotationReport -Report $Report -Format Json
            $script:Parsed = $Json | ConvertFrom-Json
        }

        It 'round-trips summary counts and metadata' {
            $Parsed.asOfDate          | Should -Be '2026-01-15'
            $Parsed.warningWindowDays | Should -Be 14
            $Parsed.summary.total     | Should -Be 4
            $Parsed.summary.expired   | Should -Be 2
            $Parsed.summary.warning   | Should -Be 1
            $Parsed.summary.ok        | Should -Be 1
        }

        It 'round-trips the grouped secrets with full detail' {
            $Parsed.expired.name              | Should -Be @('signing-key', 'db-password')
            $Parsed.expired[0].daysUntilExpiry | Should -Be -18
            $Parsed.warning[0].name            | Should -Be 'api-key'
            $Parsed.warning[0].requiredBy      | Should -Be @('web-frontend', 'mobile-app')
            $Parsed.ok[0].expiresOn            | Should -Be '2027-01-01'
        }
    }

    It 'throws a meaningful error for an unsupported format' {
        { Format-RotationReport -Report $Report -Format Xml } |
            Should -Throw '*"Xml"*'
    }
}

Describe 'Invoke-SecretRotationValidator.ps1 (CLI entry point)' {
    # TDD cycle 5: the script the CI pipeline calls. Runs in a child pwsh so
    # we can observe real stdout and exit codes exactly as CI would see them.

    BeforeAll {
        $script:ScriptPath  = Join-Path $PSScriptRoot '..' 'Invoke-SecretRotationValidator.ps1'
        $script:FixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.json'

        function script:Invoke-Cli {
            param([string[]] $CliArgs)
            $stdout = & pwsh -NoProfile -File $script:ScriptPath @CliArgs 2>&1 | Out-String
            [pscustomobject]@{ Output = $stdout; ExitCode = $LASTEXITCODE }
        }
    }

    It 'prints a markdown report and exits 0 for a healthy run' {
        $r = Invoke-Cli @('-ConfigPath', $FixturePath, '-Format', 'Markdown', '-AsOfDate', '2026-01-15')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match ([regex]::Escape('**Totals:** 4 secrets — 2 expired, 1 warning, 1 ok'))
    }

    It 'prints parseable JSON when -Format Json is requested' {
        $r = Invoke-Cli @('-ConfigPath', $FixturePath, '-Format', 'Json', '-AsOfDate', '2026-01-15')
        $r.ExitCode | Should -Be 0
        ($r.Output | ConvertFrom-Json).summary.expired | Should -Be 2
    }

    It 'exits 2 when -FailOnExpired is set and expired secrets exist' {
        $r = Invoke-Cli @('-ConfigPath', $FixturePath, '-AsOfDate', '2026-01-15', '-FailOnExpired')
        $r.ExitCode | Should -Be 2
    }

    It 'exits 1 with a meaningful message when the config file is missing' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $TestDrive 'nope.json'))
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'Config file not found'
    }

    It 'exits 1 with a meaningful message for an invalid -AsOfDate' {
        $r = Invoke-Cli @('-ConfigPath', $FixturePath, '-AsOfDate', '15/01/2026')
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match "Invalid -AsOfDate '15/01/2026'"
    }
}
