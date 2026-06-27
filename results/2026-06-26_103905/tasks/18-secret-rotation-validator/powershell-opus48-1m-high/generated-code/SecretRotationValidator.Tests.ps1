#requires -Modules Pester

# Pester tests for the Secret Rotation Validator.
# Developed red/green TDD: each Describe block was added as a failing test
# first, then the minimum implementation was written to make it pass.

BeforeAll {
    # Import the module under test. Resolve relative to this test file so the
    # suite works regardless of the caller's working directory.
    $modulePath = Join-Path $PSScriptRoot 'SecretRotationValidator.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-SecretRotationStatus - core classification' {
    It 'classifies a secret past its rotation policy as expired' {
        $secret = [pscustomobject]@{
            name        = 'db-password'
            lastRotated = '2026-01-01'
            policyDays  = 30
            requiredBy  = @('api', 'worker')
        }
        # Reference date is far past lastRotated + policyDays (2026-01-31).
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.urgency | Should -Be 'expired'
        $result.daysUntilDue | Should -BeLessThan 0
    }

    It 'classifies a secret due within the warning window as warning' {
        $secret = [pscustomobject]@{
            name = 'tls-cert'; lastRotated = '2026-06-01'; policyDays = 30; requiredBy = @('ingress')
        }
        # Due 2026-07-01; reference 2026-06-27 => 4 days out, within 14-day window.
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.urgency | Should -Be 'warning'
        $result.daysUntilDue | Should -Be 4
    }

    It 'classifies a secret due far in the future as ok' {
        $secret = [pscustomobject]@{
            name = 'api-key'; lastRotated = '2026-06-01'; policyDays = 90; requiredBy = @('api')
        }
        # Due 2026-08-30; reference 2026-06-27 => 64 days out.
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.urgency | Should -Be 'ok'
        $result.daysUntilDue | Should -Be 64
    }

    It 'treats a secret due exactly today (0 days) as warning, not expired' {
        $secret = [pscustomobject]@{
            name = 'edge-today'; lastRotated = '2026-05-28'; policyDays = 30; requiredBy = @()
        }
        # Due 2026-06-27 == reference date => daysUntilDue 0 => warning (boundary).
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.daysUntilDue | Should -Be 0
        $result.urgency | Should -Be 'warning'
    }

    It 'treats a secret due exactly at the warning-window edge as warning' {
        $secret = [pscustomobject]@{
            name = 'edge-window'; lastRotated = '2026-06-12'; policyDays = 30; requiredBy = @()
        }
        # Due 2026-07-12; reference 2026-06-27 => 15 days. With WarningDays=15 => warning.
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 15
        $result.daysUntilDue | Should -Be 15
        $result.urgency | Should -Be 'warning'
    }

    It 'computes the due date as lastRotated + policyDays' {
        $secret = [pscustomobject]@{
            name = 'due-calc'; lastRotated = '2026-01-01'; policyDays = 30; requiredBy = @()
        }
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.dueDate | Should -Be '2026-01-31'
    }

    It 'preserves the requiredBy services on the result' {
        $secret = [pscustomobject]@{
            name = 'multi'; lastRotated = '2026-06-01'; policyDays = 90; requiredBy = @('api', 'worker', 'cron')
        }
        $result = Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' -WarningDays 14
        $result.requiredBy | Should -Be @('api', 'worker', 'cron')
    }
}

Describe 'Get-SecretRotationStatus - error handling' {
    It 'throws a meaningful error for an unparseable lastRotated date' {
        $secret = [pscustomobject]@{
            name = 'bad-date'; lastRotated = 'not-a-date'; policyDays = 30; requiredBy = @()
        }
        { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' } |
            Should -Throw "*unparseable lastRotated*"
    }

    It 'throws a meaningful error for a non-positive policyDays' {
        $secret = [pscustomobject]@{
            name = 'bad-policy'; lastRotated = '2026-06-01'; policyDays = 0; requiredBy = @()
        }
        { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' } |
            Should -Throw "*invalid policyDays*"
    }

    It 'throws when a required field is missing' {
        $secret = [pscustomobject]@{ name = 'no-policy'; lastRotated = '2026-06-01' }
        { Get-SecretRotationStatus -Secret $secret -ReferenceDate '2026-06-27' } |
            Should -Throw "*missing required field 'policyDays'*"
    }
}

Describe 'Get-SecretRotationReport - aggregation and grouping' {
    BeforeAll {
        # A representative mix: one of each urgency level.
        $script:secrets = @(
            [pscustomobject]@{ name = 'expired-1'; lastRotated = '2026-01-01'; policyDays = 30; requiredBy = @('api') }
            [pscustomobject]@{ name = 'warning-1'; lastRotated = '2026-06-01'; policyDays = 30; requiredBy = @('ingress') }
            [pscustomobject]@{ name = 'ok-1';      lastRotated = '2026-06-01'; policyDays = 90; requiredBy = @('worker') }
            [pscustomobject]@{ name = 'expired-2'; lastRotated = '2026-02-01'; policyDays = 30; requiredBy = @('cron') }
        )
    }

    It 'returns a report object with grouped buckets and a summary' {
        $report = Get-SecretRotationReport -Secrets $script:secrets -ReferenceDate '2026-06-27' -WarningDays 14
        $report.summary.expired | Should -Be 2
        $report.summary.warning | Should -Be 1
        $report.summary.ok      | Should -Be 1
        $report.summary.total   | Should -Be 4
    }

    It 'sorts results expired-first, then warning, then ok, by daysUntilDue ascending' {
        $report = Get-SecretRotationReport -Secrets $script:secrets -ReferenceDate '2026-06-27' -WarningDays 14
        $order = $report.secrets | ForEach-Object { $_.urgency }
        $order | Should -Be @('expired', 'expired', 'warning', 'ok')
        # Within expired, the most-overdue (most negative daysUntilDue) comes first.
        $report.secrets[0].name | Should -Be 'expired-1'
        $report.secrets[1].name | Should -Be 'expired-2'
    }

    It 'exposes per-urgency groups for notification routing' {
        $report = Get-SecretRotationReport -Secrets $script:secrets -ReferenceDate '2026-06-27' -WarningDays 14
        $report.groups.expired.Count | Should -Be 2
        $report.groups.warning.Count | Should -Be 1
        $report.groups.ok.Count      | Should -Be 1
        ($report.groups.expired | ForEach-Object name) | Should -Contain 'expired-1'
    }

    It 'carries the reference date and warning window into the report metadata' {
        $report = Get-SecretRotationReport -Secrets $script:secrets -ReferenceDate '2026-06-27' -WarningDays 21
        $report.referenceDate | Should -Be '2026-06-27'
        $report.warningDays   | Should -Be 21
    }

    It 'handles an empty secret set without error' {
        $report = Get-SecretRotationReport -Secrets @() -ReferenceDate '2026-06-27' -WarningDays 14
        $report.summary.total | Should -Be 0
        $report.secrets.Count | Should -Be 0
    }
}

Describe 'Format-RotationReport - markdown output' {
    BeforeAll {
        $script:report = Get-SecretRotationReport -Secrets @(
            [pscustomobject]@{ name = 'expired-1'; lastRotated = '2026-01-01'; policyDays = 30; requiredBy = @('api', 'worker') }
            [pscustomobject]@{ name = 'warning-1'; lastRotated = '2026-06-01'; policyDays = 30; requiredBy = @('ingress') }
            [pscustomobject]@{ name = 'ok-1';      lastRotated = '2026-06-01'; policyDays = 90; requiredBy = @('worker') }
        ) -ReferenceDate '2026-06-27' -WarningDays 14
    }

    It 'renders a markdown table with a header row and separator' {
        $md = Format-RotationReport -Report $script:report -Format markdown
        $md | Should -Match '\| *Secret *\| *Urgency *\|'
        $md | Should -Match '\| *-+ *\|'
    }

    It 'includes a summary line with the counts' {
        $md = Format-RotationReport -Report $script:report -Format markdown
        $md | Should -Match 'Expired:\s*1'
        $md | Should -Match 'Warning:\s*1'
        $md | Should -Match 'OK:\s*1'
    }

    It 'renders one data row per secret with its name and joined services' {
        $md = Format-RotationReport -Report $script:report -Format markdown
        $md | Should -Match 'expired-1'
        $md | Should -Match 'api, worker'   # requiredBy joined for display
    }

    It 'renders an explicit no-secrets message for an empty report' {
        $empty = Get-SecretRotationReport -Secrets @() -ReferenceDate '2026-06-27' -WarningDays 14
        $md = Format-RotationReport -Report $empty -Format markdown
        $md | Should -Match 'No secrets'
    }
}

Describe 'Format-RotationReport - JSON output' {
    BeforeAll {
        $script:report = Get-SecretRotationReport -Secrets @(
            [pscustomobject]@{ name = 'expired-1'; lastRotated = '2026-01-01'; policyDays = 30; requiredBy = @('api') }
            [pscustomobject]@{ name = 'ok-1';      lastRotated = '2026-06-01'; policyDays = 90; requiredBy = @('worker') }
        ) -ReferenceDate '2026-06-27' -WarningDays 14
    }

    It 'emits valid JSON that round-trips' {
        $json = Format-RotationReport -Report $script:report -Format json
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'preserves the summary counts and secret details in JSON' {
        $json = Format-RotationReport -Report $script:report -Format json
        $obj = $json | ConvertFrom-Json
        $obj.summary.expired | Should -Be 1
        $obj.summary.ok      | Should -Be 1
        $obj.summary.total   | Should -Be 2
        $obj.secrets[0].name | Should -Be 'expired-1'
        $obj.secrets[0].urgency | Should -Be 'expired'
    }
}

Describe 'Format-RotationReport - validation' {
    It 'rejects an unsupported format with a clear error' {
        $report = Get-SecretRotationReport -Secrets @() -ReferenceDate '2026-06-27' -WarningDays 14
        { Format-RotationReport -Report $report -Format xml } | Should -Throw
    }
}

Describe 'Import-SecretConfig - loading fixtures from disk' {
    BeforeAll {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("srv-test-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmpDir | Out-Null
    }
    AfterAll {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force }
    }

    It 'loads an array of secrets from a JSON file' {
        $path = Join-Path $script:tmpDir 'array.json'
        '[{"name":"a","lastRotated":"2026-01-01","policyDays":30,"requiredBy":["api"]}]' | Set-Content $path
        $secrets = Import-SecretConfig -Path $path
        $secrets.Count | Should -Be 1
        $secrets[0].name | Should -Be 'a'
    }

    It 'loads secrets wrapped in a top-level "secrets" property' {
        $path = Join-Path $script:tmpDir 'wrapped.json'
        '{"secrets":[{"name":"b","lastRotated":"2026-01-01","policyDays":30,"requiredBy":[]}]}' | Set-Content $path
        $secrets = Import-SecretConfig -Path $path
        $secrets.Count | Should -Be 1
        $secrets[0].name | Should -Be 'b'
    }

    It 'throws a clear error when the file does not exist' {
        { Import-SecretConfig -Path (Join-Path $script:tmpDir 'missing.json') } |
            Should -Throw "*not found*"
    }

    It 'throws a clear error when the file contains invalid JSON' {
        $path = Join-Path $script:tmpDir 'bad.json'
        'this is not json {{{' | Set-Content $path
        { Import-SecretConfig -Path $path } | Should -Throw "*invalid JSON*"
    }
}

Describe 'Invoke-Validator.ps1 - CLI entrypoint' {
    BeforeAll {
        $script:cli = Join-Path $PSScriptRoot 'Invoke-Validator.ps1'
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("srv-cli-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmpDir | Out-Null

        $script:configPath = Join-Path $script:tmpDir 'secrets.json'
        @'
[
  {"name":"db-password","lastRotated":"2026-01-01","policyDays":30,"requiredBy":["api","worker"]},
  {"name":"tls-cert","lastRotated":"2026-06-01","policyDays":30,"requiredBy":["ingress"]},
  {"name":"api-key","lastRotated":"2026-06-01","policyDays":90,"requiredBy":["api"]}
]
'@ | Set-Content $script:configPath
    }
    AfterAll {
        if (Test-Path $script:tmpDir) { Remove-Item $script:tmpDir -Recurse -Force }
    }

    It 'prints a markdown report and exits 0 when no secrets are expired' {
        # api-key only: rotated recently, 90-day policy => ok.
        $okConfig = Join-Path $script:tmpDir 'ok.json'
        '[{"name":"api-key","lastRotated":"2026-06-01","policyDays":90,"requiredBy":["api"]}]' | Set-Content $okConfig
        $out = pwsh -NoProfile -File $script:cli -ConfigPath $okConfig -ReferenceDate '2026-06-27' -WarningDays 14 -Format markdown
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'OK:\s*1'
    }

    It 'exits non-zero (gate failure) when expired secrets are present and -FailOnExpired is set' {
        $out = pwsh -NoProfile -File $script:cli -ConfigPath $script:configPath -ReferenceDate '2026-06-27' -WarningDays 14 -Format markdown -FailOnExpired
        $LASTEXITCODE | Should -Be 2
        ($out -join "`n") | Should -Match 'db-password'
    }

    It 'emits valid JSON when -Format json is requested' {
        $out = pwsh -NoProfile -File $script:cli -ConfigPath $script:configPath -ReferenceDate '2026-06-27' -WarningDays 14 -Format json
        $LASTEXITCODE | Should -Be 0
        $obj = ($out -join "`n") | ConvertFrom-Json
        $obj.summary.total | Should -Be 3
        $obj.summary.expired | Should -Be 1
    }

    It 'exits non-zero with a clear message when the config file is missing' {
        $out = pwsh -NoProfile -File $script:cli -ConfigPath (Join-Path $script:tmpDir 'nope.json') -ReferenceDate '2026-06-27' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'not found'
    }
}
