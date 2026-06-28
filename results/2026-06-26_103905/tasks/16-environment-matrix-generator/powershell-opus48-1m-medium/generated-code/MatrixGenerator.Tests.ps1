#Requires -Modules Pester

# Pester tests for MatrixGenerator.ps1, driven by red/green TDD.
# The script is dot-sourced so its functions are available to the tests
# without executing the CLI entry point.

BeforeAll {
    . "$PSScriptRoot/MatrixGenerator.ps1"
}

Describe 'Expand-Matrix (cartesian product)' {
    It 'produces a single empty combination for no dimensions' {
        $result = Expand-Matrix -Dimensions @{}
        $result | Should -HaveCount 1
        $result[0].Count | Should -Be 0
    }

    It 'produces one combination per value for a single dimension' {
        $result = Expand-Matrix -Dimensions @{ os = @('linux', 'windows') }
        $result | Should -HaveCount 2
        @($result | ForEach-Object { $_.os }) | Should -Be @('linux', 'windows')
    }

    It 'produces the full cartesian product for multiple dimensions' {
        $result = Expand-Matrix -Dimensions ([ordered]@{
            os   = @('linux', 'windows')
            node = @(18, 20)
        })
        $result | Should -HaveCount 4
    }

    It 'throws when a dimension has no values' {
        { Expand-Matrix -Dimensions @{ os = @() } } |
            Should -Throw -ExpectedMessage "*has no values*"
    }
}

Describe 'Remove-Excludes' {
    It 'removes combinations that fully match an exclude rule' {
        $combos = Expand-Matrix -Dimensions ([ordered]@{
            os   = @('linux', 'windows')
            node = @(18, 20)
        })
        $result = Remove-Excludes -Combinations $combos -Excludes @(
            [ordered]@{ os = 'windows'; node = 18 }
        )
        $result | Should -HaveCount 3
    }

    It 'treats exclude rules as partial matches' {
        $combos = Expand-Matrix -Dimensions ([ordered]@{
            os   = @('linux', 'windows')
            node = @(18, 20)
        })
        # Excluding just os=windows should drop both windows combinations.
        $result = Remove-Excludes -Combinations $combos -Excludes @(
            [ordered]@{ os = 'windows' }
        )
        $result | Should -HaveCount 2
        @($result | ForEach-Object { $_.os }) | Should -Be @('linux', 'linux')
    }

    It 'returns all combinations when there are no excludes' {
        $combos = Expand-Matrix -Dimensions @{ os = @('linux') }
        (Remove-Excludes -Combinations $combos -Excludes @()) | Should -HaveCount 1
    }
}

Describe 'Add-Includes' {
    It 'extends matching combinations with new keys' {
        $combos = Expand-Matrix -Dimensions @{ os = @('linux', 'windows') }
        $result = Add-Includes -Combinations $combos `
            -Includes @( [ordered]@{ os = 'linux'; experimental = $true } ) `
            -DimensionKeys @('os')
        $result | Should -HaveCount 2
        $linux = $result | Where-Object { $_.os -eq 'linux' }
        $linux.experimental | Should -BeTrue
        $win = $result | Where-Object { $_.os -eq 'windows' }
        $win.Contains('experimental') | Should -BeFalse
    }

    It 'appends a new combination when an include matches nothing' {
        $combos = Expand-Matrix -Dimensions @{ os = @('linux') }
        $result = Add-Includes -Combinations $combos `
            -Includes @( [ordered]@{ os = 'macos'; node = 20 } ) `
            -DimensionKeys @('os')
        $result | Should -HaveCount 2
        ($result | Where-Object { $_.os -eq 'macos' }).node | Should -Be 20
    }

    It 'never overwrites an original dimension value' {
        $combos = Expand-Matrix -Dimensions @{ os = @('linux') }
        # include shares the 'os' dimension with a DIFFERENT value -> it cannot
        # merge into the linux combo, so it becomes a new combination.
        $result = Add-Includes -Combinations $combos `
            -Includes @( [ordered]@{ os = 'windows' } ) `
            -DimensionKeys @('os')
        $result | Should -HaveCount 2
    }
}

Describe 'New-BuildMatrix (end to end)' {
    It 'builds a full matrix with strategy settings' {
        $config = [pscustomobject]@{
            matrix      = [pscustomobject]@{
                os   = @('ubuntu-latest', 'windows-latest')
                node = @(18, 20)
            }
            maxParallel = 4
            failFast    = $false
        }
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 4
        $result.'max-parallel' | Should -Be 4
        $result.'fail-fast' | Should -BeFalse
        $result.matrix.include | Should -HaveCount 4
    }

    It 'defaults fail-fast to true and omits max-parallel when unset' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{ os = @('ubuntu-latest') }
        }
        $result = New-BuildMatrix -Config $config
        $result.'fail-fast' | Should -BeTrue
        $result.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
    }

    It 'applies excludes then includes together' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{
                os   = @('linux', 'windows')
                node = @(18, 20)
                exclude = @( [pscustomobject]@{ os = 'windows'; node = 18 } )
                include = @( [pscustomobject]@{ os = 'linux'; node = 18; coverage = $true } )
            }
        }
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 3
        $covered = $result.matrix.include | Where-Object { $_.coverage }
        $covered | Should -HaveCount 1
        $covered.os | Should -Be 'linux'
        $covered.node | Should -Be 18
    }

    It 'supports an include-only matrix (no base dimensions)' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{
                include = @(
                    [pscustomobject]@{ os = 'linux'; node = 20 }
                    [pscustomobject]@{ os = 'macos'; node = 18 }
                )
            }
        }
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 2
    }

    It 'throws when the matrix exceeds maxSize' {
        $config = [pscustomobject]@{
            matrix  = [pscustomobject]@{
                os   = @('a', 'b', 'c')
                node = @(1, 2, 3)
            }
            maxSize = 8
        }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage "*exceeds the maximum allowed size of 8*"
    }

    It 'throws when no matrix key is present' {
        { New-BuildMatrix -Config ([pscustomobject]@{ foo = 1 }) } |
            Should -Throw -ExpectedMessage "*must contain a 'matrix' object*"
    }

    It 'throws when every combination is excluded' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{
                os = @('linux')
                exclude = @( [pscustomobject]@{ os = 'linux' } )
            }
        }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage "*matrix is empty*"
    }

    It 'handles a three-dimension feature-flag matrix' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{
                os      = @('ubuntu-latest', 'windows-latest')
                node    = @(18, 20)
                feature = @('on', 'off')
            }
        }
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 8
    }
}

Describe 'Invoke-MatrixGenerator (CLI / JSON IO)' {
    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mg-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
    }
    AfterAll {
        if (Test-Path $script:tmp) { Remove-Item -Recurse -Force $script:tmp }
    }

    It 'reads a config file and writes valid JSON output' {
        $configPath = Join-Path $script:tmp 'config.json'
        $outPath = Join-Path $script:tmp 'out.json'
        @{
            matrix      = @{ os = @('ubuntu-latest', 'windows-latest'); node = @(18, 20) }
            maxParallel = 2
            failFast    = $false
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath

        Invoke-MatrixGenerator -ConfigPath $configPath -OutputPath $outPath | Out-Null

        Test-Path $outPath | Should -BeTrue
        $parsed = Get-Content $outPath -Raw | ConvertFrom-Json
        $parsed.size | Should -Be 4
        $parsed.'max-parallel' | Should -Be 2
        $parsed.'fail-fast' | Should -BeFalse
        $parsed.matrix.include | Should -HaveCount 4
    }

    It 'throws a meaningful error for a missing config file' {
        { Invoke-MatrixGenerator -ConfigPath (Join-Path $script:tmp 'nope.json') } |
            Should -Throw -ExpectedMessage "*Config file not found*"
    }

    It 'throws a meaningful error for malformed JSON' {
        $bad = Join-Path $script:tmp 'bad.json'
        '{ this is not json' | Set-Content -LiteralPath $bad
        { Invoke-MatrixGenerator -ConfigPath $bad } |
            Should -Throw -ExpectedMessage "*Failed to parse config JSON*"
    }
}
