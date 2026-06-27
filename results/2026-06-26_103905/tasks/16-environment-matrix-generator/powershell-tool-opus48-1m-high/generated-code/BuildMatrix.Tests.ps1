# BuildMatrix.Tests.ps1
#
# Pester 5 tests for the build-matrix generator.
#
# These tests were written test-first (red/green TDD). Each Describe block
# corresponds to a unit of functionality that was implemented only after the
# test for it failed for the right reason.
#
# Run with:  Invoke-Pester -Path ./BuildMatrix.Tests.ps1

BeforeAll {
    # Import the module under test. $PSScriptRoot is the directory of this file.
    $script:ModulePath = Join-Path $PSScriptRoot 'BuildMatrix.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Expand-MatrixAxes (cartesian product)' {

    It 'expands a single axis into one combination per value' {
        $axes = [ordered]@{ os = @('ubuntu-latest', 'windows-latest') }
        $result = Expand-MatrixAxes -Axes $axes

        $result.Count | Should -Be 2
        $result[0].os | Should -Be 'ubuntu-latest'
        $result[1].os | Should -Be 'windows-latest'
    }

    It 'produces the cartesian product of two axes in odometer order (first axis slowest)' {
        $axes = [ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        }
        $result = Expand-MatrixAxes -Axes $axes

        $result.Count | Should -Be 4
        # First axis varies slowest, last axis varies fastest.
        ($result | ForEach-Object { "$($_.os)/$($_.node)" }) | Should -Be @(
            'ubuntu-latest/18',
            'ubuntu-latest/20',
            'windows-latest/18',
            'windows-latest/20'
        )
    }

    It 'preserves boolean feature-flag values as real booleans' {
        $axes = [ordered]@{
            os           = @('ubuntu-latest')
            experimental = @($true, $false)
        }
        $result = Expand-MatrixAxes -Axes $axes

        $result.Count | Should -Be 2
        $result[0].experimental | Should -BeOfType [bool]
        $result[0].experimental | Should -BeTrue
        $result[1].experimental | Should -BeFalse
    }

    It 'returns an empty list when there are no axes' {
        $result = Expand-MatrixAxes -Axes ([ordered]@{})
        @($result).Count | Should -Be 0
    }
}

Describe 'Remove-ExcludedCombinations (exclude rules)' {

    BeforeEach {
        $script:combos = Expand-MatrixAxes -Axes ([ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        })
    }

    It 'removes combinations that match an exclude rule on every key' {
        $exclude = @(
            [ordered]@{ os = 'windows-latest'; node = '18' }
        )
        $result = Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude

        @($result).Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }) | Should -BeNullOrEmpty
    }

    It 'treats an exclude rule as a partial match (removes all combos matching the given keys)' {
        $exclude = @(
            [ordered]@{ os = 'windows-latest' }
        )
        $result = Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude

        @($result).Count | Should -Be 2
        ($result | ForEach-Object { $_.os } | Sort-Object -Unique) | Should -Be 'ubuntu-latest'
    }

    It 'returns combinations unchanged when there are no exclude rules' {
        $result = Remove-ExcludedCombinations -Combinations $script:combos -Exclude @()
        @($result).Count | Should -Be 4
    }

    It 'matches boolean values correctly when excluding' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{
            os           = @('ubuntu-latest', 'windows-latest')
            experimental = @($true, $false)
        })
        $exclude = @(
            [ordered]@{ os = 'windows-latest'; experimental = $true }
        )
        $result = Remove-ExcludedCombinations -Combinations $combos -Exclude $exclude

        @($result).Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.experimental -eq $true }) | Should -BeNullOrEmpty
    }
}

Describe 'Add-IncludedCombinations (include rules)' {

    It 'adds a new key to every combination when the include has no axis keys' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{ os = @('ubuntu-latest', 'windows-latest') })
        $axisNames = @('os')
        $include = @( [ordered]@{ color = 'green' } )

        $result = Add-IncludedCombinations -Combinations $combos -Include $include -AxisNames $axisNames

        @($result).Count | Should -Be 2
        ($result | ForEach-Object { $_.color } | Sort-Object -Unique) | Should -Be 'green'
    }

    It 'extends only matching combinations when the include constrains an axis key' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        })
        $include = @( [ordered]@{ os = 'ubuntu-latest'; coverage = $true } )

        $result = Add-IncludedCombinations -Combinations $combos -Include $include -AxisNames @('os', 'node')

        @($result).Count | Should -Be 4
        ($result | Where-Object { $_.os -eq 'ubuntu-latest' } | ForEach-Object { $_.coverage }) | Should -Be @($true, $true)
        # windows combos must NOT have gained the coverage key.
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.Contains('coverage') }) | Should -BeNullOrEmpty
    }

    It 'creates a brand-new combination when the include cannot extend any existing one' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{ os = @('ubuntu-latest') })
        # node is not an axis here, but os=macos-latest does not exist, so this
        # is a fresh standalone combination.
        $include = @( [ordered]@{ os = 'macos-latest'; node = '21' } )

        $result = Add-IncludedCombinations -Combinations $combos -Include $include -AxisNames @('os')

        @($result).Count | Should -Be 2
        $new = $result | Where-Object { $_.os -eq 'macos-latest' }
        $new.node | Should -Be '21'
    }

    It 'reproduces the canonical GitHub Actions fruit/animal include example exactly' {
        # https://docs.github.com/actions - the documented include semantics.
        $combos = Expand-MatrixAxes -Axes ([ordered]@{
            fruit  = @('apple', 'pear')
            animal = @('cat', 'dog')
        })
        $include = @(
            [ordered]@{ color = 'green' }
            [ordered]@{ color = 'pink'; animal = 'cat' }
            [ordered]@{ fruit = 'apple'; shape = 'circle' }
            [ordered]@{ fruit = 'banana' }
            [ordered]@{ fruit = 'banana'; animal = 'cat' }
        )

        $result = Add-IncludedCombinations -Combinations $combos -Include $include -AxisNames @('fruit', 'animal')

        # Serialize each combo to a stable string for comparison.
        $asString = $result | ForEach-Object {
            $combo = $_
            $pairs = foreach ($k in $combo.Keys) { "$k=$($combo[$k])" }
            $pairs -join ','
        }

        $expected = @(
            'fruit=apple,animal=cat,color=pink,shape=circle'
            'fruit=apple,animal=dog,color=green,shape=circle'
            'fruit=pear,animal=cat,color=pink'
            'fruit=pear,animal=dog,color=green'
            'fruit=banana'
            'fruit=banana,animal=cat'
        )
        $asString | Should -Be $expected
    }

    It 'returns combinations unchanged when there are no include rules' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{ os = @('ubuntu-latest') })
        $result = Add-IncludedCombinations -Combinations $combos -Include @() -AxisNames @('os')
        @($result).Count | Should -Be 1
    }
}

Describe 'Assert-MatrixSize (size validation)' {

    It 'does not throw when the matrix is within the limit' {
        $combos = @([ordered]@{ a = 1 }, [ordered]@{ a = 2 })
        { Assert-MatrixSize -Combinations $combos -MaxSize 5 } | Should -Not -Throw
    }

    It 'does not throw when the matrix is exactly at the limit' {
        $combos = @([ordered]@{ a = 1 }, [ordered]@{ a = 2 })
        { Assert-MatrixSize -Combinations $combos -MaxSize 2 } | Should -Not -Throw
    }

    It 'throws a meaningful error when the matrix exceeds the limit' {
        $combos = @([ordered]@{ a = 1 }, [ordered]@{ a = 2 }, [ordered]@{ a = 3 })
        { Assert-MatrixSize -Combinations $combos -MaxSize 2 } |
            Should -Throw -ExpectedMessage '*exceeds the maximum allowed size*'
    }

    It 'reports the actual and maximum sizes in the error message' {
        $combos = @([ordered]@{ a = 1 }, [ordered]@{ a = 2 }, [ordered]@{ a = 3 })
        $msg = $null
        try { Assert-MatrixSize -Combinations $combos -MaxSize 2 }
        catch { $msg = $_.Exception.Message }
        $msg | Should -Match '3'
        $msg | Should -Match '2'
    }
}

Describe 'New-BuildMatrix (orchestration)' {

    It 'builds a strategy object from a simple OS x version config' {
        $config = @{
            matrix = [ordered]@{
                os   = @('ubuntu-latest', 'windows-latest')
                node = @('18', '20')
            }
        }
        $strategy = New-BuildMatrix -Config $config

        $strategy.matrix.include.Count | Should -Be 4
        $strategy.'fail-fast' | Should -BeTrue   # GitHub default
        $strategy.Contains('max-parallel') | Should -BeFalse
    }

    It 'applies exclude then include rules and feature flags together' {
        $config = @{
            matrix = [ordered]@{
                os           = @('ubuntu-latest', 'windows-latest')
                node         = @('18', '20')
                experimental = @($false)
                exclude      = @( [ordered]@{ os = 'windows-latest'; node = '18' } )
                include      = @( [ordered]@{ os = 'ubuntu-latest'; node = '20'; coverage = $true } )
            }
        }
        $strategy = New-BuildMatrix -Config $config

        # 4 base - 1 excluded = 3 combos; include extends an existing one.
        $strategy.matrix.include.Count | Should -Be 3
        $covered = $strategy.matrix.include | Where-Object { $_.Contains('coverage') }
        @($covered).Count | Should -Be 1
        $covered.os | Should -Be 'ubuntu-latest'
        $covered.node | Should -Be '20'
    }

    It 'passes through fail-fast and max-parallel from the config' {
        $config = @{
            'fail-fast'    = $false
            'max-parallel' = 3
            matrix         = [ordered]@{ os = @('ubuntu-latest') }
        }
        $strategy = New-BuildMatrix -Config $config

        $strategy.'fail-fast' | Should -BeFalse
        $strategy.'max-parallel' | Should -Be 3
    }

    It 'enforces max-size and throws when exceeded' {
        $config = @{
            'max-size' = 2
            matrix     = [ordered]@{ os = @('ubuntu-latest', 'windows-latest', 'macos-latest') }
        }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage '*exceeds the maximum allowed size*'
    }

    It 'throws a meaningful error when no matrix axes are provided' {
        $config = @{ matrix = [ordered]@{} }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage '*at least one axis*'
    }

    It 'throws when the config has no matrix key at all' {
        { New-BuildMatrix -Config @{ 'fail-fast' = $true } } |
            Should -Throw -ExpectedMessage "*'matrix'*"
    }

    It 'accepts a PSCustomObject config as produced by ConvertFrom-Json' {
        $json = @'
{
  "fail-fast": false,
  "max-parallel": 2,
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "experimental": [true, false]
  }
}
'@
        $config = $json | ConvertFrom-Json
        $strategy = New-BuildMatrix -Config $config

        $strategy.matrix.include.Count | Should -Be 4
        $strategy.'fail-fast' | Should -BeFalse
        $strategy.'max-parallel' | Should -Be 2
        # Boolean axis must survive the round-trip as a real boolean.
        ($strategy.matrix.include | Where-Object { $_.experimental -eq $true }).Count | Should -Be 2
    }
}

Describe 'ConvertTo-StrategyJson (JSON emission)' {

    It 'emits valid JSON that round-trips back to the same strategy' {
        $strategy = New-BuildMatrix -Config @{
            matrix = [ordered]@{ os = @('ubuntu-latest', 'windows-latest') }
        }
        $json = ConvertTo-StrategyJson -Strategy $strategy
        $back = $json | ConvertFrom-Json

        $back.matrix.include.Count | Should -Be 2
        $back.'fail-fast' | Should -BeTrue
    }

    It 'keeps a single-combination include as a JSON array, not a bare object' {
        $strategy = New-BuildMatrix -Config @{
            matrix = [ordered]@{ os = @('ubuntu-latest') }
        }
        $json = ConvertTo-StrategyJson -Strategy $strategy

        # The include value must be a JSON array even with one element.
        $json | Should -Match '"include"\s*:\s*\['
        $back = $json | ConvertFrom-Json
        # ConvertFrom-Json yields an array we can index when it is a real array.
        @($back.matrix.include).Count | Should -Be 1
    }

    It 'emits feature flags as JSON booleans (true/false), not strings' {
        $strategy = New-BuildMatrix -Config @{
            matrix = [ordered]@{ os = @('ubuntu-latest'); experimental = @($true, $false) }
        }
        $json = ConvertTo-StrategyJson -Strategy $strategy

        $json | Should -Match '"experimental"\s*:\s*true'
        $json | Should -Match '"experimental"\s*:\s*false'
        $json | Should -Not -Match '"experimental"\s*:\s*"true"'
    }
}

Describe 'Generate-Matrix.ps1 (CLI entry point)' {

    BeforeAll {
        $script:Cli = Join-Path $PSScriptRoot 'Generate-Matrix.ps1'
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("genmatrix-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TmpDir) { Remove-Item $script:TmpDir -Recurse -Force }
    }

    It 'exists as a script file' {
        Test-Path $script:Cli | Should -BeTrue
    }

    It 'reads a JSON config file and prints a STRATEGY_JSON line that parses to the resolved matrix' {
        $cfgPath = Join-Path $script:TmpDir 'basic.json'
        @'
{ "matrix": { "os": ["ubuntu-latest", "windows-latest"], "node": ["18", "20"] } }
'@ | Set-Content -Path $cfgPath -Encoding utf8

        $out = & pwsh -NoProfile -File $script:Cli -ConfigPath $cfgPath
        $LASTEXITCODE | Should -Be 0

        $line = ($out | Where-Object { $_ -match '^STRATEGY_JSON=' })
        $line | Should -Not -BeNullOrEmpty
        $strategy = ($line -replace '^STRATEGY_JSON=', '') | ConvertFrom-Json
        $strategy.matrix.include.Count | Should -Be 4
        $strategy.'fail-fast' | Should -BeTrue
    }

    It 'writes step outputs when GITHUB_OUTPUT is set' {
        $cfgPath = Join-Path $script:TmpDir 'ff.json'
        @'
{ "fail-fast": false, "max-parallel": 2, "matrix": { "os": ["ubuntu-latest"] } }
'@ | Set-Content -Path $cfgPath -Encoding utf8
        $ghOut = Join-Path $script:TmpDir 'gh_output.txt'
        Set-Content -Path $ghOut -Value '' -Encoding utf8

        & pwsh -NoProfile -Command "`$env:GITHUB_OUTPUT='$ghOut'; & '$($script:Cli)' -ConfigPath '$cfgPath'" | Out-Null
        $LASTEXITCODE | Should -Be 0

        $outContent = Get-Content -Path $ghOut -Raw
        $outContent | Should -Match 'matrix=\{'
        $outContent | Should -Match 'fail-fast=False'
        $outContent | Should -Match 'max-parallel=2'

        # The matrix output must itself be valid JSON with an include array.
        $matrixLine = (Get-Content -Path $ghOut | Where-Object { $_ -match '^matrix=' }) -replace '^matrix=', ''
        $m = $matrixLine | ConvertFrom-Json
        @($m.include).Count | Should -Be 1
    }

    It 'exits non-zero with a meaningful message when the config file is missing' {
        $missing = Join-Path $script:TmpDir 'does-not-exist.json'
        $err = & pwsh -NoProfile -File $script:Cli -ConfigPath $missing 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($err -join "`n") | Should -Match 'not found|does not exist|Cannot find'
    }

    It 'exits non-zero when the matrix would exceed max-size' {
        $cfgPath = Join-Path $script:TmpDir 'toobig.json'
        @'
{ "max-size": 2, "matrix": { "os": ["a", "b", "c"] } }
'@ | Set-Content -Path $cfgPath -Encoding utf8
        $err = & pwsh -NoProfile -File $script:Cli -ConfigPath $cfgPath 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($err -join "`n") | Should -Match 'exceeds the maximum allowed size'
    }
}
