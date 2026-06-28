#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Pester tests for the Secret Rotation Validator.

    These tests were written test-first (red/green/refactor). Each Describe block
    drives out one piece of behaviour in the SecretRotation module:
      * Get-SecretStatus      - the core date classification (Expired/Warning/Ok)
      * Import-SecretConfig    - loading and validating a JSON config (error handling)
      * Get-RotationReport     - grouping secrets by urgency into a report object
      * Format-RotationReport  - rendering the report as markdown or JSON
      * Get-RotationNotification - the per-secret notification lines

    A fixed -ReferenceDate is threaded through every test so the suite is fully
    deterministic and never depends on the real wall-clock.
#>

BeforeAll {
    # Import the module under test fresh on every run so edits are picked up.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'SecretRotation.psm1'
    Import-Module $script:ModulePath -Force

    # The single reference "now" used across the whole suite.
    $script:Ref = [datetime]'2026-06-28'
}

Describe 'Get-SecretStatus' {

    It 'classifies an overdue secret as Expired and reports days overdue' {
        $result = Get-SecretStatus -LastRotated ([datetime]'2026-01-01') `
            -RotationPolicyDays 90 -ReferenceDate $script:Ref -WarningDays 14

        $result.Status          | Should -Be 'Expired'
        $result.ExpiryDate      | Should -Be ([datetime]'2026-04-01')
        $result.DaysUntilExpiry | Should -Be -88
    }

    It 'classifies a secret expiring inside the warning window as Warning' {
        $result = Get-SecretStatus -LastRotated ([datetime]'2026-04-01') `
            -RotationPolicyDays 90 -ReferenceDate $script:Ref -WarningDays 14

        $result.Status          | Should -Be 'Warning'
        $result.DaysUntilExpiry | Should -Be 2
    }

    It 'classifies a secret with plenty of time left as Ok' {
        $result = Get-SecretStatus -LastRotated ([datetime]'2026-06-01') `
            -RotationPolicyDays 90 -ReferenceDate $script:Ref -WarningDays 14

        $result.Status          | Should -Be 'Ok'
        $result.DaysUntilExpiry | Should -Be 63
    }

    Context 'boundary conditions' {
        It 'treats expiring exactly today (0 days) as Warning, not Expired' {
            # last rotated exactly RotationPolicyDays ago -> expires today
            $result = Get-SecretStatus -LastRotated ($script:Ref.AddDays(-30)) `
                -RotationPolicyDays 30 -ReferenceDate $script:Ref -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 0
            $result.Status          | Should -Be 'Warning'
        }

        It 'treats one day overdue as Expired' {
            $result = Get-SecretStatus -LastRotated ($script:Ref.AddDays(-31)) `
                -RotationPolicyDays 30 -ReferenceDate $script:Ref -WarningDays 14
            $result.DaysUntilExpiry | Should -Be -1
            $result.Status          | Should -Be 'Expired'
        }

        It 'treats expiry exactly on the warning-window edge as Warning' {
            $result = Get-SecretStatus -LastRotated $script:Ref `
                -RotationPolicyDays 14 -ReferenceDate $script:Ref -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 14
            $result.Status          | Should -Be 'Warning'
        }

        It 'treats expiry one day past the warning-window edge as Ok' {
            $result = Get-SecretStatus -LastRotated $script:Ref `
                -RotationPolicyDays 15 -ReferenceDate $script:Ref -WarningDays 14
            $result.DaysUntilExpiry | Should -Be 15
            $result.Status          | Should -Be 'Ok'
        }

        It 'honours a different (configurable) warning window' {
            # 20 days out is Ok with a 14-day window but Warning with a 30-day window
            $args = @{ LastRotated = $script:Ref; RotationPolicyDays = 20; ReferenceDate = $script:Ref }
            (Get-SecretStatus @args -WarningDays 14).Status | Should -Be 'Ok'
            (Get-SecretStatus @args -WarningDays 30).Status | Should -Be 'Warning'
        }
    }
}

Describe 'Import-SecretConfig' {

    BeforeAll {
        $script:FixtureDir = Join-Path $TestDrive 'cfg'
        New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null
    }

    It 'loads a well-formed config and returns its secrets' {
        $path = Join-Path $script:FixtureDir 'good.json'
        @{
            secrets = @(
                @{ name = 'db'; lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('api') }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8

        $config = Import-SecretConfig -Path $path
        $config.Secrets             | Should -HaveCount 1
        $config.Secrets[0].name     | Should -Be 'db'
        $config.Secrets[0].requiredBy | Should -Contain 'api'
    }

    It 'accepts a bare top-level array of secrets' {
        $path = Join-Path $script:FixtureDir 'array.json'
        ,@(
            @{ name = 'token'; lastRotated = '2026-01-01'; rotationPolicyDays = 30; requiredBy = @('svc') }
        ) | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8

        (Import-SecretConfig -Path $path).Secrets | Should -HaveCount 1
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $script:FixtureDir 'nope.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error on invalid JSON' {
        $path = Join-Path $script:FixtureDir 'bad.json'
        '{ this is not json' | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage '*Invalid JSON*'
    }

    It 'throws when a secret is missing a required field' {
        $path = Join-Path $script:FixtureDir 'missing.json'
        @{ secrets = @( @{ name = 'db'; rotationPolicyDays = 90 } ) } |
            ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage "*lastRotated*"
    }

    It 'throws when lastRotated is not a valid date' {
        $path = Join-Path $script:FixtureDir 'baddate.json'
        @{ secrets = @( @{ name = 'db'; lastRotated = 'not-a-date'; rotationPolicyDays = 90; requiredBy = @('api') } ) } |
            ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage '*lastRotated*'
    }

    It 'throws when rotationPolicyDays is not a positive integer' {
        $path = Join-Path $script:FixtureDir 'badpolicy.json'
        @{ secrets = @( @{ name = 'db'; lastRotated = '2026-01-01'; rotationPolicyDays = 0; requiredBy = @('api') } ) } |
            ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
        { Import-SecretConfig -Path $path } | Should -Throw -ExpectedMessage '*rotationPolicyDays*'
    }
}

Describe 'Get-RotationReport' {

    BeforeAll {
        # A representative mix: one expired, one warning, one ok.
        $script:MixedSecrets = @(
            [pscustomobject]@{ name = 'legacy-db-password';   lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('billing-api', 'reports-worker') }
            [pscustomobject]@{ name = 'payments-api-key';     lastRotated = '2026-04-01'; rotationPolicyDays = 90; requiredBy = @('payments-gateway') }
            [pscustomobject]@{ name = 'session-cache-secret'; lastRotated = '2026-06-01'; rotationPolicyDays = 90; requiredBy = @('web-frontend') }
        )
        $script:Report = Get-RotationReport -Secrets $script:MixedSecrets `
            -ReferenceDate $script:Ref -WarningDays 14
    }

    It 'records the reference date and warning window on the report' {
        $script:Report.ReferenceDate | Should -Be $script:Ref
        $script:Report.WarningDays   | Should -Be 14
    }

    It 'summarises the counts per urgency' {
        $script:Report.Summary.Expired | Should -Be 1
        $script:Report.Summary.Warning | Should -Be 1
        $script:Report.Summary.Ok      | Should -Be 1
        $script:Report.Summary.Total   | Should -Be 3
    }

    It 'groups each secret under the correct urgency bucket' {
        $script:Report.Groups.Expired.Name | Should -Be 'legacy-db-password'
        $script:Report.Groups.Warning.Name | Should -Be 'payments-api-key'
        $script:Report.Groups.Ok.Name      | Should -Be 'session-cache-secret'
    }

    It 'enriches each entry with computed status fields' {
        $expired = $script:Report.Groups.Expired[0]
        $expired.Status          | Should -Be 'Expired'
        $expired.DaysUntilExpiry | Should -Be -88
        $expired.ExpiryDate      | Should -Be ([datetime]'2026-04-01')
        $expired.RotationPolicyDays | Should -Be 90
        $expired.RequiredBy      | Should -Contain 'reports-worker'
    }

    It 'produces empty (count 0) groups when a bucket has no members' {
        $allOk = @(
            [pscustomobject]@{ name = 'fresh'; lastRotated = '2026-06-20'; rotationPolicyDays = 365; requiredBy = @('svc') }
        )
        $report = Get-RotationReport -Secrets $allOk -ReferenceDate $script:Ref -WarningDays 14
        $report.Summary.Expired   | Should -Be 0
        @($report.Groups.Expired) | Should -HaveCount 0
        @($report.Groups.Warning) | Should -HaveCount 0
        @($report.Groups.Ok)      | Should -HaveCount 1
    }
}

Describe 'Format-RotationReport' {

    BeforeAll {
        $secrets = @(
            [pscustomobject]@{ name = 'legacy-db-password';   lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('billing-api', 'reports-worker') }
            [pscustomobject]@{ name = 'payments-api-key';     lastRotated = '2026-04-01'; rotationPolicyDays = 90; requiredBy = @('payments-gateway') }
            [pscustomobject]@{ name = 'session-cache-secret'; lastRotated = '2026-06-01'; rotationPolicyDays = 90; requiredBy = @('web-frontend') }
        )
        $script:Report = Get-RotationReport -Secrets $secrets -ReferenceDate $script:Ref -WarningDays 14
    }

    Context 'markdown format' {
        BeforeAll { $script:Md = Format-RotationReport -Report $script:Report -Format Markdown }

        It 'has a title and report metadata' {
            $script:Md | Should -Match '# Secret Rotation Report'
            $script:Md | Should -Match 'Reference date: 2026-06-28'
            $script:Md | Should -Match 'Warning window: 14'
        }

        It 'has a summary table with the per-urgency counts' {
            $script:Md | Should -Match '\| Expired \| 1 \|'
            $script:Md | Should -Match '\| Warning \| 1 \|'
            $script:Md | Should -Match '\| OK \| 1 \|'
        }

        It 'has a section per urgency with a count in the heading' {
            $script:Md | Should -Match '## Expired \(1\)'
            $script:Md | Should -Match '## Warning \(1\)'
            $script:Md | Should -Match '## OK \(1\)'
        }

        It 'renders an expired secret row with overdue days and required-by services' {
            $script:Md | Should -Match 'legacy-db-password'
            # overdue 88, expiry 2026-04-01, services comma-joined
            $script:Md | Should -Match '\| legacy-db-password \| 2026-01-01 \| 90 \| 2026-04-01 \| 88 \| billing-api, reports-worker \|'
        }

        It 'renders the warning and ok rows with days-until-expiry' {
            $script:Md | Should -Match '\| payments-api-key \| 2026-04-01 \| 90 \| 2026-06-30 \| 2 \| payments-gateway \|'
            $script:Md | Should -Match '\| session-cache-secret \| 2026-06-01 \| 90 \| 2026-08-30 \| 63 \| web-frontend \|'
        }
    }

    Context 'json format' {
        BeforeAll {
            $script:Json   = Format-RotationReport -Report $script:Report -Format Json
            $script:Parsed = $script:Json | ConvertFrom-Json
        }

        It 'emits valid JSON' {
            { $script:Json | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'carries the metadata and summary' {
            $script:Parsed.referenceDate     | Should -Be '2026-06-28'
            $script:Parsed.warningWindowDays | Should -Be 14
            $script:Parsed.summary.expired   | Should -Be 1
            $script:Parsed.summary.warning   | Should -Be 1
            $script:Parsed.summary.ok        | Should -Be 1
            $script:Parsed.summary.total     | Should -Be 3
        }

        It 'carries each group with formatted dates and computed days' {
            $exp = $script:Parsed.groups.expired[0]
            $exp.name            | Should -Be 'legacy-db-password'
            $exp.lastRotated     | Should -Be '2026-01-01'
            $exp.expiryDate      | Should -Be '2026-04-01'
            $exp.daysUntilExpiry | Should -Be -88
            $exp.status          | Should -Be 'Expired'
            $exp.requiredBy      | Should -Contain 'reports-worker'
        }
    }

    It 'throws on an unsupported format' {
        { Format-RotationReport -Report $script:Report -Format Yaml } | Should -Throw
    }
}

Describe 'Get-RotationNotification' {

    BeforeAll {
        $secrets = @(
            [pscustomobject]@{ name = 'legacy-db-password';   lastRotated = '2026-01-01'; rotationPolicyDays = 90; requiredBy = @('billing-api', 'reports-worker') }
            [pscustomobject]@{ name = 'payments-api-key';     lastRotated = '2026-04-01'; rotationPolicyDays = 90; requiredBy = @('payments-gateway') }
            [pscustomobject]@{ name = 'session-cache-secret'; lastRotated = '2026-06-01'; rotationPolicyDays = 90; requiredBy = @('web-frontend') }
        )
        $report = Get-RotationReport -Secrets $secrets -ReferenceDate $script:Ref -WarningDays 14
        $script:Lines = @(Get-RotationNotification -Report $report)
    }

    It 'emits one notification line per secret, ordered expired -> warning -> ok' {
        $script:Lines             | Should -HaveCount 3
        $script:Lines[0]          | Should -BeLike 'NOTIFY EXPIRED *'
        $script:Lines[1]          | Should -BeLike 'NOTIFY WARNING *'
        $script:Lines[2]          | Should -BeLike 'NOTIFY OK *'
    }

    It 'reports overdue days for expired and days-until for warning/ok, with services' {
        $script:Lines[0] | Should -Be 'NOTIFY EXPIRED legacy-db-password overdue=88 requiredBy=billing-api,reports-worker'
        $script:Lines[1] | Should -Be 'NOTIFY WARNING payments-api-key days=2 requiredBy=payments-gateway'
        $script:Lines[2] | Should -Be 'NOTIFY OK session-cache-secret days=63 requiredBy=web-frontend'
    }
}

Describe 'Invoke-SecretRotationValidator.ps1 (CLI entry point)' {

    BeforeAll {
        $script:Cli     = Join-Path $PSScriptRoot '..' 'Invoke-SecretRotationValidator.ps1'
        $script:CaseDir = Join-Path $PSScriptRoot '..' 'fixtures' 'cases'

        # Run the CLI in a child pwsh so we can assert on its real exit code
        # without 'exit' terminating the Pester host. Returns stdout+stderr text
        # plus the process exit code.
        function Invoke-Cli {
            param([string[]]$CliArgs)
            $merged = & pwsh -NoProfile -File $script:Cli @CliArgs 2>&1
            [pscustomobject]@{
                Output   = ($merged | Out-String)
                ExitCode = $LASTEXITCODE
            }
        }
    }

    It 'on the mixed fixture exits 0 and prints the exact summary line' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'mixed.json'),
            '-ReferenceDate', '2026-06-28', '-WarningDays', '14', '-Format', 'markdown')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'SUMMARY expired=1 warning=1 ok=1 total=3'
    }

    It 'prints the exact grouped notification lines' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'mixed.json'),
            '-ReferenceDate', '2026-06-28', '-WarningDays', '14', '-Format', 'markdown')
        $r.Output | Should -Match 'NOTIFY EXPIRED legacy-db-password overdue=88 requiredBy=billing-api,reports-worker'
        $r.Output | Should -Match 'NOTIFY WARNING payments-api-key days=2 requiredBy=payments-gateway'
        $r.Output | Should -Match 'NOTIFY OK session-cache-secret days=63 requiredBy=web-frontend'
    }

    It 'wraps the markdown report in delimiters' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'mixed.json'),
            '-ReferenceDate', '2026-06-28', '-Format', 'markdown')
        $r.Output | Should -Match '<<<REPORT FORMAT=markdown>>>'
        $r.Output | Should -Match '# Secret Rotation Report'
        $r.Output | Should -Match '<<<END REPORT>>>'
    }

    It 'emits parseable JSON when -Format json' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'mixed.json'),
            '-ReferenceDate', '2026-06-28', '-Format', 'json')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match '<<<REPORT FORMAT=json>>>'
        # Extract the JSON block and parse it.
        $json = ($r.Output -split '<<<REPORT FORMAT=json>>>')[1] -split '<<<END REPORT>>>' | Select-Object -First 1
        $obj  = $json | ConvertFrom-Json
        $obj.summary.expired | Should -Be 1
        $obj.groups.warning[0].name | Should -Be 'payments-api-key'
    }

    It 'on the all-ok fixture reports zero expired/zero warning' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'all-ok.json'),
            '-ReferenceDate', '2026-06-28', '-WarningDays', '14', '-Format', 'markdown')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'SUMMARY expired=0 warning=0 ok=2 total=2'
    }

    It 'on the all-expired fixture reports both as expired with exact overdue days' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'all-expired.json'),
            '-ReferenceDate', '2026-06-28', '-WarningDays', '14', '-Format', 'markdown')
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'SUMMARY expired=2 warning=0 ok=0 total=2'
        $r.Output   | Should -Match 'NOTIFY EXPIRED ancient-root-cred overdue=58'
        $r.Output   | Should -Match 'NOTIFY EXPIRED expired-tls-cert overdue=28'
    }

    It 'exits 1 with a meaningful message when the config is missing' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'does-not-exist.json'),
            '-ReferenceDate', '2026-06-28')
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'not found'
    }

    It 'exits 2 when -FailOnExpired is set and expired secrets exist' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'mixed.json'),
            '-ReferenceDate', '2026-06-28', '-FailOnExpired')
        $r.ExitCode | Should -Be 2
    }

    It 'exits 0 with -FailOnExpired when no secrets are expired' {
        $r = Invoke-Cli @('-ConfigPath', (Join-Path $script:CaseDir 'all-ok.json'),
            '-ReferenceDate', '2026-06-28', '-FailOnExpired')
        $r.ExitCode | Should -Be 0
    }
}
