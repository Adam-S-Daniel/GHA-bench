<#
    Tests for the CLI entrypoint script Invoke-SecretRotationCheck.ps1.
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '..' 'Invoke-SecretRotationCheck.ps1'
    $script:fixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.sample.json'
    $script:allOkFixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'secrets.allok.json'
}

Describe 'Invoke-SecretRotationCheck.ps1' {

    It 'exits with code 1 and prints a warning when any secret is expired (Markdown format)' {
        $output = & $script:scriptPath -ConfigPath $script:fixturePath -WarningDays 7 -AsOf '2026-07-01' -Format Markdown
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 1
        ($output -join "`n") | Should -Match 'db-password'
        ($output -join "`n") | Should -Match 'Expired'
    }

    It 'exits with code 0 when no secrets are expired or in warning' {
        $output = & $script:scriptPath -ConfigPath $script:allOkFixturePath -WarningDays 7 -AsOf '2026-07-01' -Format Markdown
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match 'healthy-secret'
    }

    It 'supports JSON output format' {
        $output = & $script:scriptPath -ConfigPath $script:fixturePath -WarningDays 7 -AsOf '2026-07-01' -Format Json
        $json = ($output -join "`n") | ConvertFrom-Json

        $json.Summary.TotalCount | Should -Be 3
        $json.Expired.Name | Should -Be 'db-password'
    }

    It 'throws a meaningful error for a missing config file' {
        { & $script:scriptPath -ConfigPath './nope.json' -WarningDays 7 } | Should -Throw
    }
}
