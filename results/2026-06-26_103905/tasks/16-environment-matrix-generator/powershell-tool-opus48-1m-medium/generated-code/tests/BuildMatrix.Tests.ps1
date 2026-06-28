# BuildMatrix.Tests.ps1
#
# Unit tests for the build-matrix generator, written using red/green TDD.
# Each Describe block was written FIRST (red) and the module code added to make
# it pass (green). The module exposes pure functions so the logic is testable
# without invoking GitHub Actions / act.
#
# Run with:  Invoke-Pester ./tests/BuildMatrix.Tests.ps1

BeforeAll {
    # Import the module under test. $PSScriptRoot points at the tests/ dir.
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/BuildMatrix.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-MatrixCombination (cartesian expansion)' {
    It 'expands a single dimension into one combination per value' {
        $matrix = @{ os = @('linux', 'windows') }
        $combos = Get-MatrixCombination -Matrix $matrix
        $combos.Count | Should -Be 2
        ($combos | ForEach-Object { $_.os }) | Should -Be @('linux', 'windows')
    }

    It 'produces the cartesian product of multiple dimensions' {
        $matrix = [ordered]@{
            os      = @('linux', 'windows')
            version = @('16', '18', '20')
        }
        $combos = Get-MatrixCombination -Matrix $matrix
        $combos.Count | Should -Be 6
    }

    It 'returns an empty list when there are no dimensions' {
        $combos = Get-MatrixCombination -Matrix @{}
        @($combos).Count | Should -Be 0
    }
}

Describe 'Get-MatrixCombination with exclude rules' {
    It 'removes combinations matching all key/value pairs of an exclude entry' {
        $matrix = [ordered]@{
            os      = @('linux', 'windows')
            version = @('16', '18')
        }
        $exclude = @(@{ os = 'windows'; version = '16' })
        $combos = Get-MatrixCombination -Matrix $matrix -Exclude $exclude
        $combos.Count | Should -Be 3
        ($combos | Where-Object { $_.os -eq 'windows' -and $_.version -eq '16' }).Count | Should -Be 0
    }

    It 'treats a partial exclude as a wildcard over the unspecified keys' {
        $matrix = [ordered]@{
            os      = @('linux', 'windows')
            version = @('16', '18')
        }
        $exclude = @(@{ os = 'windows' })
        $combos = Get-MatrixCombination -Matrix $matrix -Exclude $exclude
        $combos.Count | Should -Be 2
        ($combos | Where-Object { $_.os -eq 'windows' }).Count | Should -Be 0
    }
}

Describe 'Get-MatrixCombination with include rules' {
    It 'merges extra keys into matching combinations without overwriting matrix values' {
        $matrix   = [ordered]@{ os = @('linux', 'windows') }
        $include  = @(@{ os = 'linux'; arch = 'arm64' })
        $combos   = Get-MatrixCombination -Matrix $matrix -Include $include
        $combos.Count | Should -Be 2
        ($combos | Where-Object { $_.os -eq 'linux' }).arch | Should -Be 'arm64'
        ($combos | Where-Object { $_.os -eq 'windows' }).Contains('arch') | Should -Be $false
    }

    It 'adds a brand new combination when the include cannot merge' {
        $matrix  = [ordered]@{ os = @('linux') }
        $include = @(@{ os = 'macos'; experimental = $true })
        $combos  = Get-MatrixCombination -Matrix $matrix -Include $include
        $combos.Count | Should -Be 2
        ($combos | Where-Object { $_.os -eq 'macos' }).experimental | Should -Be $true
    }
}

Describe 'New-BuildMatrix (full strategy object)' {
    It 'emits a strategy object with fail-fast and max-parallel' {
        $config = @{
            matrix       = [ordered]@{ os = @('linux'); version = @('18') }
            'fail-fast'  = $false
            'max-parallel' = 2
        }
        $result = New-BuildMatrix -Config $config
        $result.strategy.'fail-fast'   | Should -Be $false
        $result.strategy.'max-parallel' | Should -Be 2
        $result.strategy.matrix.os     | Should -Be @('linux')
        $result.jobCount               | Should -Be 1
    }

    It 'throws a meaningful error when the matrix exceeds max-size' {
        $config = @{
            matrix     = [ordered]@{ os = @('a', 'b', 'c'); version = @('1', '2') }
            'max-size' = 4
        }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage '*exceeds the maximum allowed size*'
    }

    It 'defaults fail-fast to true and omits max-parallel when unspecified' {
        $config = @{ matrix = [ordered]@{ os = @('linux') } }
        $result = New-BuildMatrix -Config $config
        $result.strategy.'fail-fast' | Should -Be $true
        $result.strategy.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
    }
}

Describe 'ConvertTo-MatrixJson and config loading' {
    It 'round-trips a config file into matrix JSON' {
        $tmp = New-TemporaryFile
        try {
            $cfg = @{
                matrix = [ordered]@{ os = @('linux', 'windows'); version = @('18') }
                'fail-fast' = $true
            } | ConvertTo-Json -Depth 10
            Set-Content -Path $tmp -Value $cfg
            $json = Invoke-MatrixGenerator -ConfigPath $tmp
            $parsed = $json | ConvertFrom-Json
            $parsed.strategy.matrix.os.Count | Should -Be 2
            $parsed.jobCount | Should -Be 2
        }
        finally {
            Remove-Item $tmp -Force
        }
    }

    It 'throws a clear error when the config file does not exist' {
        { Invoke-MatrixGenerator -ConfigPath '/nonexistent/does-not-exist.json' } |
            Should -Throw -ExpectedMessage '*Configuration file not found*'
    }

    It 'throws a clear error when the config has no matrix section' {
        $tmp = New-TemporaryFile
        try {
            Set-Content -Path $tmp -Value '{"fail-fast": true}'
            { Invoke-MatrixGenerator -ConfigPath $tmp } |
                Should -Throw -ExpectedMessage "*'matrix'*"
        }
        finally {
            Remove-Item $tmp -Force
        }
    }
}
