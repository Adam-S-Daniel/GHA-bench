# Unit tests for the environment matrix generator module.
#
# TDD approach: each Describe block was added red-first (failing), then the
# minimum implementation was written in src/MatrixGenerator.psm1 to pass it.
#
# These tests also run INSIDE the GitHub Actions workflow (via act), so they
# must not depend on anything outside the repo.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'MatrixGenerator.psm1') -Force
}

Describe 'Expand-MatrixCombination' {
    It 'expands a 2x2 dimension set into 4 combinations in row-major order' {
        $dimensions = [ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        }

        $combos = Expand-MatrixCombination -Dimensions $dimensions

        $combos.Count | Should -Be 4
        # Row-major: first dimension varies slowest, last varies fastest.
        $combos[0].os   | Should -Be 'ubuntu-latest'
        $combos[0].node | Should -Be '18'
        $combos[1].os   | Should -Be 'ubuntu-latest'
        $combos[1].node | Should -Be '20'
        $combos[2].os   | Should -Be 'windows-latest'
        $combos[2].node | Should -Be '18'
        $combos[3].os   | Should -Be 'windows-latest'
        $combos[3].node | Should -Be '20'
    }
}

Describe 'New-BuildMatrix include/exclude rules' {
    It 'removes combinations that partially match an exclude rule' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{
                os     = @('ubuntu-latest', 'macos-latest')
                python = @('3.11', '3.12')
            }
            exclude = @([pscustomobject]@{ os = 'macos-latest'; python = '3.11' })
        }

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 3
        # The excluded macos/3.11 combination must be gone.
        $excluded = @($matrix.matrix.include | Where-Object { $_.os -eq 'macos-latest' -and $_.python -eq '3.11' })
        $excluded.Count | Should -Be 0
    }

    It 'exclude rules use partial matching (a single-key rule removes all combos with that value)' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{
                os     = @('ubuntu-latest', 'macos-latest')
                python = @('3.11', '3.12')
            }
            exclude = @([pscustomobject]@{ os = 'macos-latest' })
        }

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 2
        @($matrix.matrix.include | Where-Object { $_.os -eq 'macos-latest' }).Count | Should -Be 0
    }

    It 'appends include rules as extra combinations after the expanded product' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{
                os     = @('ubuntu-latest')
                python = @('3.11')
            }
            include = @([pscustomobject]@{ os = 'ubuntu-latest'; python = '3.13'; experimental = $true })
        }

        $matrix = New-BuildMatrix -Config $config

        $matrix.matrix.include.Count | Should -Be 2
        $last = $matrix.matrix.include[-1]
        $last.python       | Should -Be '3.13'
        $last.experimental | Should -BeTrue
    }
}

Describe 'New-BuildMatrix strategy settings' {
    It 'carries fail-fast and max-parallel from the config' {
        $config = [pscustomobject]@{
            dimensions  = [pscustomobject]@{ os = @('ubuntu-latest') }
            failFast    = $false
            maxParallel = 3
        }

        $matrix = New-BuildMatrix -Config $config

        $matrix.'fail-fast'    | Should -BeFalse
        $matrix.'max-parallel' | Should -Be 3
    }

    It 'defaults fail-fast to true and omits max-parallel when unspecified' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{ os = @('ubuntu-latest') }
        }

        $matrix = New-BuildMatrix -Config $config

        $matrix.'fail-fast' | Should -BeTrue
        $matrix.PSObject.Properties.Name -contains 'max-parallel' | Should -BeFalse
        $matrix.Keys -contains 'max-parallel' | Should -BeFalse
    }
}

Describe 'New-BuildMatrix validation and errors' {
    It 'throws a meaningful error when the matrix exceeds maxSize' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{
                os   = @('ubuntu-latest', 'windows-latest')
                node = @('18', '20')
                flag = @($true, $false)
            }
            maxSize = 4
        }

        { New-BuildMatrix -Config $config } |
            Should -Throw '*Matrix size 8 exceeds maximum allowed size 4*'
    }

    It 'counts size after excludes and includes are applied' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{
                os   = @('ubuntu-latest', 'windows-latest')
                node = @('18', '20')
            }
            exclude = @([pscustomobject]@{ os = 'windows-latest' })
            maxSize = 2
        }

        # 4 raw combos, 2 after exclude — should fit within maxSize 2.
        { New-BuildMatrix -Config $config } | Should -Not -Throw
    }

    It 'throws when the config has no dimensions' {
        $config = [pscustomobject]@{ dimensions = [pscustomobject]@{} }

        { New-BuildMatrix -Config $config } |
            Should -Throw '*must define at least one dimension*'
    }

    It 'throws when a dimension has an empty value list' {
        $config = [pscustomobject]@{
            dimensions = [pscustomobject]@{ os = @() }
        }

        { New-BuildMatrix -Config $config } |
            Should -Throw "*Dimension 'os' has no values*"
    }
}

Describe 'ConvertTo-MatrixJson' {
    It 'serializes the include-exclude fixture to the exact compressed JSON' {
        $config = Get-Content (Join-Path $PSScriptRoot '..' 'fixtures' 'include-exclude.json') -Raw |
            ConvertFrom-Json
        $matrix = New-BuildMatrix -Config $config

        $json = ConvertTo-MatrixJson -Matrix $matrix

        $expected = '{"fail-fast":false,"max-parallel":3,"matrix":{"include":[' +
            '{"os":"ubuntu-latest","python":"3.11"},' +
            '{"os":"ubuntu-latest","python":"3.12"},' +
            '{"os":"macos-latest","python":"3.12"},' +
            '{"os":"ubuntu-latest","python":"3.13","experimental":true}]}}'
        $json | Should -BeExactly $expected
    }
}

Describe 'New-EnvironmentMatrix.ps1 CLI script' {
    BeforeAll {
        $script:cli = Join-Path $PSScriptRoot '..' 'src' 'New-EnvironmentMatrix.ps1'
    }

    It 'prints the exact matrix JSON for the basic fixture and exits 0' {
        $out = & $script:cli -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'basic.json')
        $LASTEXITCODE | Should -Be 0

        $expected = '{"fail-fast":true,"max-parallel":2,"matrix":{"include":[' +
            '{"os":"ubuntu-latest","node":"18"},' +
            '{"os":"ubuntu-latest","node":"20"},' +
            '{"os":"windows-latest","node":"18"},' +
            '{"os":"windows-latest","node":"20"}]}}'
        $out | Should -BeExactly $expected
    }

    It 'fails with a meaningful error when the config file does not exist' {
        $out = & $script:cli -ConfigPath (Join-Path $PSScriptRoot 'no-such-file.json') 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'Config file not found'
    }

    It 'fails with a meaningful error when the config is not valid JSON' {
        $out = & $script:cli -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'invalid.json') 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'not valid JSON'
    }

    It 'fails with the size error for the too-large fixture' {
        $out = & $script:cli -ConfigPath (Join-Path $PSScriptRoot '..' 'fixtures' 'too-large.json') 2>&1
        $LASTEXITCODE | Should -Be 1
        "$out" | Should -Match 'Matrix size 8 exceeds maximum allowed size 4'
    }
}
