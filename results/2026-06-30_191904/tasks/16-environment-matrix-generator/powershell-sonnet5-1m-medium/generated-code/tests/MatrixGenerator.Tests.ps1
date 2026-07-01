#Requires -Modules Pester
<#
    TDD test suite for the Environment Matrix Generator.
    Tests are written before implementation and drive the design of
    src/MatrixGenerator.psm1. Run with: Invoke-Pester -Path tests/
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../src/MatrixGenerator.psm1'
    Import-Module $modulePath -Force
}

Describe 'New-EnvironmentMatrix - basic cross product' {

    It 'produces the full cartesian product of two dimensions' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest')
            language_version = @('3.9', '3.10')
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.matrix.include.Count | Should -Be 4
    }

    It 'each combination contains every dimension key' {
        $config = @{
            os               = @('ubuntu-latest')
            language_version = @('3.9', '3.10', '3.11')
        }

        $result = New-EnvironmentMatrix -Config $config

        foreach ($combo in $result.matrix.include) {
            $combo.os | Should -Be 'ubuntu-latest'
            $combo.language_version | Should -BeIn @('3.9', '3.10', '3.11')
        }
    }

    It 'throws a meaningful error when config has no dimensions' {
        { New-EnvironmentMatrix -Config @{} } | Should -Throw '*at least one dimension*'
    }

    It 'throws a meaningful error when a dimension value is not an array' {
        $config = @{ os = 'ubuntu-latest' }
        { New-EnvironmentMatrix -Config $config } | Should -Throw '*must be an array*'
    }
}

Describe 'New-EnvironmentMatrix - exclude rules' {

    It 'removes combinations that match every key of an exclude entry' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest')
            language_version = @('3.9', '3.10')
            exclude          = @(
                @{ os = 'windows-latest'; language_version = '3.9' }
            )
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.matrix.include.Count | Should -Be 3
        $excluded = $result.matrix.include | Where-Object { $_.os -eq 'windows-latest' -and $_.language_version -eq '3.9' }
        $excluded | Should -BeNullOrEmpty
    }

    It 'only removes combinations matching on a subset of keys, not partial mismatches' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest')
            language_version = @('3.9', '3.10')
            exclude          = @(
                @{ os = 'windows-latest' }
            )
        }

        $result = New-EnvironmentMatrix -Config $config

        # every windows-latest combo should be excluded regardless of language_version
        ($result.matrix.include | Where-Object { $_.os -eq 'windows-latest' }).Count | Should -Be 0
        $result.matrix.include.Count | Should -Be 2
    }
}

Describe 'New-EnvironmentMatrix - include rules' {

    It 'extends matching combinations with additional keys' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest')
            language_version = @('3.9', '3.10')
            include          = @(
                @{ os = 'ubuntu-latest'; language_version = '3.9'; experimental = $true }
            )
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.matrix.include.Count | Should -Be 4
        $extended = $result.matrix.include | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.language_version -eq '3.9' }
        $extended.experimental | Should -Be $true
    }

    It 'adds an entirely new combination when the include entry matches nothing' {
        $config = @{
            os               = @('ubuntu-latest')
            language_version = @('3.9')
            include          = @(
                @{ os = 'macos-latest'; language_version = '3.11' }
            )
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.matrix.include.Count | Should -Be 2
        $added = $result.matrix.include | Where-Object { $_.os -eq 'macos-latest' }
        $added.language_version | Should -Be '3.11'
    }
}

Describe 'New-EnvironmentMatrix - max-parallel and fail-fast' {

    It 'passes max_parallel through as max-parallel on the result' {
        $config = @{
            os           = @('ubuntu-latest', 'windows-latest')
            max_parallel = 2
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.'max-parallel' | Should -Be 2
    }

    It 'passes fail_fast through as fail-fast on the result' {
        $config = @{
            os        = @('ubuntu-latest')
            fail_fast = $false
        }

        $result = New-EnvironmentMatrix -Config $config

        $result.'fail-fast' | Should -Be $false
    }

    It 'defaults fail-fast to true when not specified' {
        $config = @{ os = @('ubuntu-latest') }

        $result = New-EnvironmentMatrix -Config $config

        $result.'fail-fast' | Should -Be $true
    }

    It 'omits max-parallel when not specified' {
        $config = @{ os = @('ubuntu-latest') }

        $result = New-EnvironmentMatrix -Config $config

        $result.Contains('max-parallel') | Should -Be $false
    }

    It 'throws a meaningful error when max_parallel is less than 1' {
        $config = @{
            os           = @('ubuntu-latest')
            max_parallel = 0
        }

        { New-EnvironmentMatrix -Config $config } | Should -Throw '*max_parallel*'
    }
}

Describe 'New-EnvironmentMatrix - max matrix size validation' {

    It 'throws a meaningful error when the generated matrix exceeds max_matrix_size' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest', 'macos-latest')
            language_version = @('3.9', '3.10', '3.11')
            max_matrix_size  = 5
        }

        { New-EnvironmentMatrix -Config $config } | Should -Throw '*exceeds*maximum*'
    }

    It 'succeeds when the generated matrix is within max_matrix_size' {
        $config = @{
            os               = @('ubuntu-latest', 'windows-latest')
            language_version = @('3.9')
            max_matrix_size  = 5
        }

        $result = New-EnvironmentMatrix -Config $config
        $result.matrix.include.Count | Should -Be 2
    }

    It 'enforces the GitHub Actions hard cap of 256 combinations by default' {
        $osValues = 1..16 | ForEach-Object { "os-$_" }
        $versionValues = 1..17 | ForEach-Object { "v$_" }
        $config = @{
            os               = $osValues
            language_version = $versionValues
        }

        { New-EnvironmentMatrix -Config $config } | Should -Throw '*exceeds*maximum*'
    }
}
