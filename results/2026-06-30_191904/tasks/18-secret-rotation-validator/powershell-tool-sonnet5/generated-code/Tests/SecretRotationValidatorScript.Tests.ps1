#Requires -Modules Pester

# End-to-end tests for the CLI entry point (SecretRotationValidator.ps1).
# These invoke the script as a child `pwsh` process (rather than dot-sourcing
# it in-process) so that its `exit` calls terminate only the child process,
# not the Pester test runner itself -- this mirrors how the script actually
# runs in CI.

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'SecretRotationValidator.ps1'
    $FixturesPath = Join-Path $PSScriptRoot 'fixtures'

    function Invoke-Validator {
        param([string[]]$Arguments)
        $output = & pwsh -NoProfile -File $ScriptPath @Arguments 2>&1
        [PSCustomObject]@{
            Output   = ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
            ErrorText = (($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n")
            ExitCode = $LASTEXITCODE
        }
    }
}

Describe 'SecretRotationValidator.ps1 (CLI)' {

    It 'exits 0 and outputs a Markdown report by default' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'mixed-secrets.json'),
            '-AsOf', '2026-01-15'
        )
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '# Secret Rotation Report'
        $result.Output | Should -Match 'Expired: 2'
    }

    It 'outputs valid JSON when -OutputFormat Json is specified' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'mixed-secrets.json'),
            '-OutputFormat', 'Json',
            '-AsOf', '2026-01-15'
        )
        $result.ExitCode | Should -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.Summary.ExpiredCount | Should -Be 2
        $parsed.Summary.WarningCount | Should -Be 3
        $parsed.Summary.OkCount | Should -Be 1
    }

    It 'overrides the config-level WarningWindowDays when -WarningWindowDays is passed' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'mixed-secrets.json'),
            '-OutputFormat', 'Json',
            '-AsOf', '2026-01-15',
            '-WarningWindowDays', '0'
        )
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.Summary.ExpiredCount | Should -Be 2
        $parsed.Summary.WarningCount | Should -Be 1
        $parsed.Summary.OkCount | Should -Be 3
    }

    It 'exits non-zero with a clear error message when the config file is missing' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'does-not-exist.json')
        )
        $result.ExitCode | Should -Not -Be 0
        $result.ErrorText | Should -Match 'not found'
    }

    It 'exits non-zero when -FailOnExpired is set and expired secrets exist' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'mixed-secrets.json'),
            '-AsOf', '2026-01-15',
            '-FailOnExpired'
        )
        $result.ExitCode | Should -Be 1
    }

    It 'exits 0 with -FailOnExpired when there are no expired secrets' {
        $result = Invoke-Validator -Arguments @(
            '-ConfigPath', (Join-Path $FixturesPath 'all-healthy-secrets.json'),
            '-AsOf', '2026-01-15',
            '-FailOnExpired'
        )
        $result.ExitCode | Should -Be 0
    }
}
