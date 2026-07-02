#Requires -Modules Pester

# Pester test suite for the Environment Matrix Generator.
# Written test-first: each Describe block below started as a failing test
# before the corresponding function existed in MatrixGenerator.psm1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'MatrixGenerator.psm1') -Force
}

Describe 'Get-CartesianProduct' {
    It 'produces one row per combination of two axes' {
        $axes = [ordered]@{
            os      = @('ubuntu-latest', 'windows-latest')
            version = @('18', '20')
        }

        $result = Get-CartesianProduct -Axes $axes

        $result.Count | Should -Be 4
        @($result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.version -eq '18' }).Count | Should -Be 1
        @($result | Where-Object { $_.os -eq 'windows-latest' -and $_.version -eq '20' }).Count | Should -Be 1
    }

    It 'produces a single row of no keys when given no axes' {
        $axes = [ordered]@{}
        $result = Get-CartesianProduct -Axes $axes
        $result.Count | Should -Be 1
    }
}

Describe 'Remove-ExcludedCombinations' {
    It 'removes rows that match every key of an exclude rule' {
        $rows = @(
            [ordered]@{ os = 'ubuntu-latest'; version = '18' }
            [ordered]@{ os = 'ubuntu-latest'; version = '20' }
            [ordered]@{ os = 'windows-latest'; version = '18' }
        )
        $excludes = @(
            @{ os = 'windows-latest'; version = '18' }
        )

        $result = Remove-ExcludedCombinations -Rows $rows -Excludes $excludes

        $result.Count | Should -Be 2
        @($result | Where-Object { $_.os -eq 'windows-latest' }).Count | Should -Be 0
    }

    It 'leaves rows untouched when a partial match does not cover every excluded key' {
        $rows = @(
            [ordered]@{ os = 'ubuntu-latest'; version = '18' }
        )
        $excludes = @(
            @{ os = 'ubuntu-latest'; version = '99' }
        )

        $result = Remove-ExcludedCombinations -Rows $rows -Excludes $excludes

        $result.Count | Should -Be 1
    }

    It 'returns rows unchanged when no excludes are given' {
        $rows = @([ordered]@{ os = 'ubuntu-latest' })
        $result = Remove-ExcludedCombinations -Rows $rows -Excludes @()
        $result.Count | Should -Be 1
    }
}

Describe 'Merge-IncludedCombinations' {
    It 'extends an existing row when the include keys match on shared axis keys' {
        $rows = @(
            [ordered]@{ os = 'ubuntu-latest'; version = '18' }
            [ordered]@{ os = 'ubuntu-latest'; version = '20' }
        )
        $includes = @(
            @{ os = 'ubuntu-latest'; version = '20'; experimental = $true }
        )

        $result = Merge-IncludedCombinations -Rows $rows -Includes $includes -AxisKeys @('os', 'version')

        $result.Count | Should -Be 2
        $extended = $result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.version -eq '20' }
        $extended.experimental | Should -Be $true
    }

    It 'adds a brand new row when the include does not match any existing axis values' {
        $rows = @(
            [ordered]@{ os = 'ubuntu-latest'; version = '18' }
        )
        $includes = @(
            @{ os = 'macos-latest'; version = '20'; experimental = $true }
        )

        $result = Merge-IncludedCombinations -Rows $rows -Includes $includes -AxisKeys @('os', 'version')

        $result.Count | Should -Be 2
        @($result | Where-Object { $_.os -eq 'macos-latest' }).Count | Should -Be 1
    }
}

Describe 'Test-MatrixSizeLimit' {
    It 'throws a clear error when the row count exceeds the maximum' {
        $rows = 1..11 | ForEach-Object { [ordered]@{ n = $_ } }
        { Test-MatrixSizeLimit -Rows $rows -MaxSize 10 } | Should -Throw '*exceeds*10*'
    }

    It 'does not throw when the row count is within the maximum' {
        $rows = 1..5 | ForEach-Object { [ordered]@{ n = $_ } }
        { Test-MatrixSizeLimit -Rows $rows -MaxSize 10 } | Should -Not -Throw
    }
}

Describe 'New-BuildMatrix' {
    It 'builds the full matrix for the basic fixture with excludes and includes applied' {
        $config = Get-Content (Join-Path $PSScriptRoot 'fixtures/basic.json') -Raw | ConvertFrom-Json

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 4
        $matrix.'max-parallel' | Should -Be 4
        $matrix.'fail-fast' | Should -Be $false
        @($matrix.matrix.include | Where-Object { $_.os -eq 'windows-latest' -and $_.version -eq '18' }).Count | Should -Be 0
        $macos = $matrix.matrix.include | Where-Object { $_.os -eq 'macos-latest' }
        $macos.experimental | Should -Be $true
    }

    It 'defaults fail-fast to true and omits max-parallel when not configured' {
        $config = Get-Content (Join-Path $PSScriptRoot 'fixtures/minimal.json') -Raw | ConvertFrom-Json

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 1
        $matrix.'fail-fast' | Should -Be $true
        $matrix.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
    }

    It 'produces the full cartesian product for the with-flags fixture' {
        $config = Get-Content (Join-Path $PSScriptRoot 'fixtures/with-flags.json') -Raw | ConvertFrom-Json

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 12
        $matrix.'max-parallel' | Should -Be 6
        $matrix.'fail-fast' | Should -Be $true
    }

    It 'throws a validation error when the fixture matrix exceeds its configured max size' {
        $config = Get-Content (Join-Path $PSScriptRoot 'fixtures/oversized.json') -Raw | ConvertFrom-Json
        { New-BuildMatrix -Config $config } | Should -Throw '*exceeds*'
    }

    It 'throws a meaningful error when the config has no matrix axes' {
        $config = [PSCustomObject]@{}
        { New-BuildMatrix -Config $config } | Should -Throw '*matrix*'
    }
}

Describe 'Generate-Matrix.ps1 (CLI entry point)' {
    It 'reads a config file and prints the matrix JSON to stdout' {
        $script = Join-Path $PSScriptRoot 'Generate-Matrix.ps1'
        $configPath = Join-Path $PSScriptRoot 'fixtures/basic.json'

        $output = & $script -ConfigPath $configPath
        $jsonLine = $output | Where-Object { $_ -like '{*' } | Select-Object -Last 1
        $parsed = $jsonLine | ConvertFrom-Json

        $parsed.matrix.include.Count | Should -Be 4
        $parsed.'max-parallel' | Should -Be 4
    }

    It 'exits non-zero and writes a clear error for a config that is missing' {
        $script = Join-Path $PSScriptRoot 'Generate-Matrix.ps1'
        { & $script -ConfigPath (Join-Path $PSScriptRoot 'fixtures/does-not-exist.json') -ErrorAction Stop } | Should -Throw '*not*found*'
    }
}
