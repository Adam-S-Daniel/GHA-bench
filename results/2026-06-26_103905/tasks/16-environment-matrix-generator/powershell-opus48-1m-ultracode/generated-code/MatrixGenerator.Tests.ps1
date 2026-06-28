# MatrixGenerator.Tests.ps1
#
# Unit tests for the Environment Matrix Generator module, written red/green TDD style.
# These exercise the pure logic of the module directly (cartesian product, exclude /
# include rules, size validation, JSON shaping and config parsing). The end-to-end
# pipeline behaviour is verified separately through `act` in Workflow.Tests.ps1.
#
# Run with: Invoke-Pester

BeforeAll {
    # Import the module under test. Resolve relative to this test file so the suite
    # works regardless of the caller's working directory.
    $script:ModulePath = Join-Path $PSScriptRoot 'MatrixGenerator.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-CartesianProduct' {
    It 'produces the full cross-product of two axes in config order' {
        # Two axes -> 2 x 2 = 4 combinations, axis keys preserved in declaration order.
        $axes = [ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @(18, 20)
        }

        $product = Get-CartesianProduct -Axes $axes

        @($product).Count | Should -Be 4
        # First combination should be the first value of every axis.
        $product[0].os   | Should -Be 'ubuntu-latest'
        $product[0].node | Should -Be 18
        # Keys appear in declaration order (os before node).
        @($product[0].Keys) | Should -Be @('os', 'node')
    }

    It 'returns a single combination for one axis' {
        $axes = [ordered]@{ os = @('ubuntu-latest') }
        $product = Get-CartesianProduct -Axes $axes
        @($product).Count | Should -Be 1
        $product[0].os | Should -Be 'ubuntu-latest'
    }

    It 'returns no combinations when there are no axes' {
        $product = Get-CartesianProduct -Axes ([ordered]@{})
        @($product).Count | Should -Be 0
    }

    It 'yields zero combinations when any axis is empty' {
        # An empty axis collapses the product to nothing, matching GitHub.
        $axes = [ordered]@{ os = @('ubuntu-latest'); node = @() }
        $product = Get-CartesianProduct -Axes $axes
        @($product).Count | Should -Be 0
    }
}

Describe 'Test-CombinationMatch' {
    It 'matches when every filter key/value is present in the combination' {
        $combo  = [ordered]@{ os = 'macos-latest'; node = 18 }
        $filter = [ordered]@{ os = 'macos-latest' }
        Test-CombinationMatch -Combination $combo -Filter $filter | Should -BeTrue
    }

    It 'does not match when a filter value differs' {
        $combo  = [ordered]@{ os = 'macos-latest'; node = 18 }
        $filter = [ordered]@{ os = 'macos-latest'; node = 20 }
        Test-CombinationMatch -Combination $combo -Filter $filter | Should -BeFalse
    }

    It 'compares numbers and their string form as equal (GitHub treats values loosely)' {
        $combo  = [ordered]@{ node = 18 }
        $filter = [ordered]@{ node = '18' }
        Test-CombinationMatch -Combination $combo -Filter $filter | Should -BeTrue
    }
}

Describe 'Get-BuildMatrix' {
    Context 'base product and exclude rules' {
        It 'expands axes into the full product when no rules are given' {
            $config = @{
                matrix = [ordered]@{
                    os   = @('ubuntu-latest', 'windows-latest')
                    node = @(18, 20)
                }
            }
            $result = Get-BuildMatrix -Config $config
            $result.Count | Should -Be 4
            @($result.Combinations).Count | Should -Be 4
        }

        It 'removes combinations matching an exclude entry' {
            $config = @{
                matrix = [ordered]@{
                    os   = @('ubuntu-latest', 'windows-latest', 'macos-latest')
                    node = @(18, 20)
                    exclude = @(
                        [ordered]@{ os = 'macos-latest'; node = 18 }
                    )
                }
            }
            $result = Get-BuildMatrix -Config $config
            # 3 x 2 = 6, minus the single excluded pair = 5.
            $result.Count | Should -Be 5
            $excluded = $result.Combinations | Where-Object { $_.os -eq 'macos-latest' -and $_.node -eq 18 }
            @($excluded).Count | Should -Be 0
            # macos-latest with node 20 must survive.
            $kept = $result.Combinations | Where-Object { $_.os -eq 'macos-latest' -and $_.node -eq 20 }
            @($kept).Count | Should -Be 1
        }
    }

    Context 'include rules' {
        It 'adds extra keys to every compatible combination without creating new ones' {
            # An include with no axis keys is purely additive across the whole matrix.
            $config = @{
                matrix = [ordered]@{
                    os   = @('ubuntu-latest', 'windows-latest')
                    node = @(20)
                    include = @(
                        [ordered]@{ coverage = $true }
                    )
                }
            }
            $result = Get-BuildMatrix -Config $config
            $result.Count | Should -Be 2
            ($result.Combinations | ForEach-Object { $_.coverage }) | Should -Be @($true, $true)
        }

        It 'extends only combinations that match the include axis values' {
            $config = @{
                matrix = [ordered]@{
                    os   = @('ubuntu-latest', 'windows-latest')
                    node = @(20)
                    include = @(
                        [ordered]@{ os = 'windows-latest'; experimental = $true }
                    )
                }
            }
            $result = Get-BuildMatrix -Config $config
            $result.Count | Should -Be 2
            $win = $result.Combinations | Where-Object { $_.os -eq 'windows-latest' }
            $win.experimental | Should -BeTrue
            $ubuntu = $result.Combinations | Where-Object { $_.os -eq 'ubuntu-latest' }
            # The ubuntu combination never received the experimental key.
            $ubuntu.Contains('experimental') | Should -BeFalse
        }

        It 'appends a brand-new combination when an include matches nothing' {
            $config = @{
                matrix = [ordered]@{
                    os   = @('ubuntu-latest')
                    node = @(20)
                    include = @(
                        [ordered]@{ os = 'windows-latest'; node = 22; experimental = $true }
                    )
                }
            }
            $result = Get-BuildMatrix -Config $config
            $result.Count | Should -Be 2
            $new = $result.Combinations | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq 22 }
            @($new).Count | Should -Be 1
            $new.experimental | Should -BeTrue
        }

        It 'supports an include-only matrix (no base axes)' {
            $config = @{
                matrix = [ordered]@{
                    include = @(
                        [ordered]@{ os = 'ubuntu-latest'; node = 18 }
                        [ordered]@{ os = 'windows-latest'; node = 20 }
                    )
                }
            }
            $result = Get-BuildMatrix -Config $config
            $result.Count | Should -Be 2
        }
    }

    Context 'strategy knobs' {
        It 'passes through fail-fast and max-parallel' {
            $config = @{
                matrix       = [ordered]@{ os = @('ubuntu-latest') }
                'fail-fast'  = $false
                'max-parallel' = 3
            }
            $result = Get-BuildMatrix -Config $config
            $result.FailFast    | Should -BeFalse
            $result.MaxParallel | Should -Be 3
        }

        It 'defaults fail-fast to true and max-parallel to null when unset' {
            $config = @{ matrix = [ordered]@{ os = @('ubuntu-latest') } }
            $result = Get-BuildMatrix -Config $config
            $result.FailFast | Should -BeTrue
            $result.MaxParallel | Should -BeNullOrEmpty
        }
    }

    Context 'size validation' {
        It 'throws when the matrix exceeds the configured maximum size' {
            $config = @{
                matrix = [ordered]@{
                    os   = @('a', 'b', 'c', 'd', 'e')
                    node = @(1, 2, 3)
                }
                'max-size' = 10
            }
            # 5 x 3 = 15 > 10 -> must throw a meaningful, count-bearing error.
            { Get-BuildMatrix -Config $config } | Should -Throw -ErrorId 'MatrixTooLarge'
        }

        It 'reports the actual and maximum counts in the error message' {
            $config = @{
                matrix = [ordered]@{ os = @('a', 'b', 'c', 'd', 'e'); node = @(1, 2, 3) }
                'max-size' = 10
            }
            $message = $null
            try { Get-BuildMatrix -Config $config } catch { $message = $_.Exception.Message }
            $message | Should -Match '15'
            $message | Should -Match '10'
        }

        It 'does not throw when the matrix is exactly at the maximum size' {
            $config = @{
                matrix     = [ordered]@{ os = @('a', 'b'); node = @(1, 2) }
                'max-size' = 4
            }
            { Get-BuildMatrix -Config $config } | Should -Not -Throw
        }

        It 'throws when the matrix is empty (nothing to build)' {
            $config = @{
                matrix = [ordered]@{
                    os = @('ubuntu-latest')
                    exclude = @([ordered]@{ os = 'ubuntu-latest' })
                }
            }
            { Get-BuildMatrix -Config $config } | Should -Throw -ErrorId 'EmptyMatrix'
        }

        It 'throws InvalidConfig when the matrix section is missing entirely' {
            { Get-BuildMatrix -Config @{ 'fail-fast' = $true } } | Should -Throw -ErrorId 'InvalidConfig'
        }
    }
}

Describe 'ConvertTo-StrategyObject / ConvertTo-MatrixObject' {
    BeforeAll {
        $script:result = Get-BuildMatrix -Config @{
            matrix         = [ordered]@{ os = @('ubuntu-latest', 'windows-latest'); node = @(20) }
            'fail-fast'    = $false
            'max-parallel' = 2
        }
    }

    It 'shapes a strategy object with fail-fast, max-parallel and matrix.include' {
        $strategy = ConvertTo-StrategyObject -Result $script:result
        $strategy['fail-fast']    | Should -BeFalse
        $strategy['max-parallel'] | Should -Be 2
        @($strategy['matrix']['include']).Count | Should -Be 2
    }

    It 'omits max-parallel from the strategy when it was not configured' {
        $r = Get-BuildMatrix -Config @{ matrix = [ordered]@{ os = @('ubuntu-latest') } }
        $strategy = ConvertTo-StrategyObject -Result $r
        $strategy.Contains('max-parallel') | Should -BeFalse
    }

    It 'produces a matrix object usable directly by strategy.matrix' {
        $matrix = ConvertTo-MatrixObject -Result $script:result
        @($matrix.Keys) | Should -Be @('include')
        @($matrix['include']).Count | Should -Be 2
    }

    It 'round-trips through ConvertTo-Json / ConvertFrom-Json without losing combinations' {
        $strategy = ConvertTo-StrategyObject -Result $script:result
        $json = $strategy | ConvertTo-Json -Depth 10
        $back = $json | ConvertFrom-Json
        @($back.matrix.include).Count | Should -Be 2
    }
}

Describe 'Read-MatrixConfig' {
    It 'parses a JSON string into an object exposing the matrix axes' {
        $json = '{ "matrix": { "os": ["ubuntu-latest"], "node": [20] } }'
        $config = Read-MatrixConfig -Json $json
        $config.matrix.os | Should -Be @('ubuntu-latest')
    }

    It 'reads and parses a JSON file from disk' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cfg-{0}.json" -f ([guid]::NewGuid()))
        Set-Content -LiteralPath $tmp -Value '{ "matrix": { "os": ["ubuntu-latest"] } }'
        try {
            $config = Read-MatrixConfig -Path $tmp
            $config.matrix.os | Should -Be @('ubuntu-latest')
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws ConfigNotFound for a missing file' {
        { Read-MatrixConfig -Path './definitely-not-here.json' } | Should -Throw -ErrorId 'ConfigNotFound'
    }

    It 'throws InvalidJson for malformed JSON' {
        { Read-MatrixConfig -Json '{ this is not json' } | Should -Throw -ErrorId 'InvalidJson'
    }
}

Describe 'Invoke-MatrixGenerator.ps1 (CLI)' {
    BeforeAll {
        $script:Cli      = Join-Path $PSScriptRoot 'Invoke-MatrixGenerator.ps1'
        $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    }

    It 'exists' {
        Test-Path -LiteralPath $script:Cli | Should -BeTrue
    }

    It 'prints valid strategy JSON for the basic fixture' {
        $out = pwsh -NoProfile -File $script:Cli -ConfigPath (Join-Path $script:Fixtures 'basic.config.json')
        $LASTEXITCODE | Should -Be 0
        $obj = ($out -join "`n") | ConvertFrom-Json
        @($obj.matrix.include).Count | Should -Be 2
        $obj.'fail-fast' | Should -BeFalse
    }

    It 'emits MATRIX_COUNT markers with -Summary' {
        $out = pwsh -NoProfile -File $script:Cli -ConfigPath (Join-Path $script:Fixtures 'exclude.config.json') -Summary
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'MATRIX_COUNT\[exclude\.config\.json\]=5'
    }

    It 'exits non-zero with a meaningful message when the matrix is too large' {
        $out = pwsh -NoProfile -File $script:Cli -ConfigPath (Join-Path $script:Fixtures 'oversize.config.json') 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($out -join "`n") | Should -Match 'exceeds'
    }

    It 'exits non-zero for a missing config file' {
        $null = pwsh -NoProfile -File $script:Cli -ConfigPath './nope.json' 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }
}
