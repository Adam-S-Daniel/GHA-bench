#Requires -Modules Pester
<#
    TDD tests for the CLI entry point (src/Generate-Matrix.ps1) that reads a
    JSON config fixture from disk and prints the generated matrix JSON.
#>

BeforeAll {
    $script:CliPath = Join-Path $PSScriptRoot '../src/Generate-Matrix.ps1'
    $script:FixturesDir = Join-Path $PSScriptRoot '../fixtures'
}

Describe 'Generate-Matrix.ps1 CLI' {

    It 'prints valid matrix JSON for a basic config fixture' {
        $configPath = Join-Path $script:FixturesDir 'basic-config.json'

        $output = & $script:CliPath -ConfigPath $configPath
        $parsed = $output | ConvertFrom-Json

        $parsed.matrix.include.Count | Should -Be 5
        $parsed.'max-parallel' | Should -Be 4
        $parsed.'fail-fast' | Should -Be $false
    }

    It 'applies the exclude rule from the fixture' {
        $configPath = Join-Path $script:FixturesDir 'basic-config.json'

        $output = & $script:CliPath -ConfigPath $configPath
        $parsed = $output | ConvertFrom-Json

        $excluded = $parsed.matrix.include | Where-Object { $_.os -eq 'windows-latest' -and $_.language_version -eq '3.9' }
        $excluded | Should -BeNullOrEmpty
    }

    It 'applies the include rule from the fixture' {
        $configPath = Join-Path $script:FixturesDir 'basic-config.json'

        $output = & $script:CliPath -ConfigPath $configPath
        $parsed = $output | ConvertFrom-Json

        $extended = $parsed.matrix.include | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.language_version -eq '3.11' }
        $extended.experimental | Should -Be $true
    }

    It 'writes matrix, max-parallel and fail-fast lines to the GitHub output file when -GithubOutputPath is supplied' {
        $configPath = Join-Path $script:FixturesDir 'basic-config.json'
        $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "gha-output-$([guid]::NewGuid()).txt"

        try {
            & $script:CliPath -ConfigPath $configPath -GithubOutputPath $outputFile | Out-Null
            $lines = Get-Content -LiteralPath $outputFile

            ($lines | Where-Object { $_ -match '^matrix=' }).Count | Should -Be 1
            $lines | Should -Contain 'max-parallel=4'
            $lines | Should -Contain 'fail-fast=false'
        }
        finally {
            Remove-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error for a config that exceeds max_matrix_size' {
        $configPath = Join-Path $script:FixturesDir 'oversized-config.json'

        { & $script:CliPath -ConfigPath $configPath } | Should -Throw '*exceeds*maximum*'
    }

    It 'throws a meaningful error when the config file does not exist' {
        { & $script:CliPath -ConfigPath (Join-Path $script:FixturesDir 'does-not-exist.json') } | Should -Throw '*not found*'
    }
}
