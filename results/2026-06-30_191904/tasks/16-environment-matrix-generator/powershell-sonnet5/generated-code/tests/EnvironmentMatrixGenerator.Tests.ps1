# Unit tests (TDD) for the core matrix-generation logic.
# These run fast and directly exercise the module's exported functions -
# no Docker/act involved. Pipeline-level verification lives in
# Workflow.Execution.Tests.ps1, which drives the same logic through the
# real GitHub Actions workflow via `act`.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'EnvironmentMatrixGenerator.psm1'
    Import-Module $ModulePath -Force
}

Describe 'Get-MatrixCombination' {
    It 'produces the cartesian product of a single dimension' {
        $dimensions = [pscustomobject]@{ os = @('ubuntu-latest', 'windows-latest') }
        $result = Get-MatrixCombination -Dimensions $dimensions
        $result.Count | Should -Be 2
        $result[0].os | Should -Be 'ubuntu-latest'
        $result[1].os | Should -Be 'windows-latest'
    }

    It 'produces the cartesian product of two dimensions, first dimension slowest-changing' {
        $dimensions = [pscustomobject]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @(16, 18)
        }
        $result = Get-MatrixCombination -Dimensions $dimensions
        $result.Count | Should -Be 4
        $result[0].os | Should -Be 'ubuntu-latest'
        $result[0].node | Should -Be 16
        $result[1].os | Should -Be 'ubuntu-latest'
        $result[1].node | Should -Be 18
        $result[2].os | Should -Be 'windows-latest'
        $result[2].node | Should -Be 16
        $result[3].os | Should -Be 'windows-latest'
        $result[3].node | Should -Be 18
    }

    It 'throws a meaningful error when no dimensions are provided' {
        { Get-MatrixCombination -Dimensions ([pscustomobject]@{}) } | Should -Throw '*at least one dimension*'
    }

    It 'throws a meaningful error when a dimension has no values' {
        $dimensions = [pscustomobject]@{ os = @() }
        { Get-MatrixCombination -Dimensions $dimensions } | Should -Throw "*'os'*at least one value*"
    }

    It 'throws a meaningful error when the raw combination count is unreasonably large' {
        $dimensions = [pscustomobject]@{
            a = 1..500
            b = 1..500
            c = 1..500
        }
        { Get-MatrixCombination -Dimensions $dimensions } | Should -Throw '*exceeding the safety ceiling*'
    }
}

Describe 'Remove-ExcludedCombination' {
    BeforeEach {
        $script:Combos = @(
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 16 }
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 18 }
            [pscustomobject]@{ os = 'windows-latest'; node = 16 }
            [pscustomobject]@{ os = 'windows-latest'; node = 18 }
        )
        $script:Keys = @('os', 'node')
    }

    It 'removes combinations matching every key/value pair of a full-key exclude rule' {
        $rules = @([pscustomobject]@{ os = 'windows-latest'; node = 16 })
        $result = Remove-ExcludedCombination -Combination $Combos -ExcludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq 16 }) | Should -BeNullOrEmpty
    }

    It 'removes every combination matching a partial-key (subset) exclude rule' {
        $rules = @([pscustomobject]@{ os = 'windows-latest' })
        $result = Remove-ExcludedCombination -Combination $Combos -ExcludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 2
        ($result | Where-Object { $_.os -eq 'windows-latest' }) | Should -BeNullOrEmpty
    }

    It 'leaves combinations untouched when no exclude rule matches' {
        $rules = @([pscustomobject]@{ os = 'macos-latest' })
        $result = Remove-ExcludedCombination -Combination $Combos -ExcludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 4
    }

    It 'returns the input unchanged when there are no exclude rules' {
        $result = Remove-ExcludedCombination -Combination $Combos -ExcludeRule @() -DimensionKeys $Keys
        $result.Count | Should -Be 4
    }

    It 'throws a meaningful error when an exclude rule references an unknown dimension' {
        $rules = @([pscustomobject]@{ bogus = 'nope' })
        { Remove-ExcludedCombination -Combination $Combos -ExcludeRule $rules -DimensionKeys $Keys } |
            Should -Throw "*'bogus'*"
    }
}

Describe 'Merge-IncludedCombination' {
    BeforeEach {
        $script:Combos = @(
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 16 }
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 18 }
            [pscustomobject]@{ os = 'windows-latest'; node = 18 }
        )
        $script:Keys = @('os', 'node')
    }

    It 'merges extra keys into every existing combination matched on all of the rule''s base keys' {
        $rules = @([pscustomobject]@{ os = 'ubuntu-latest'; node = 18; experimental = $true })
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 3
        $matched = $result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 18 }
        $matched.experimental | Should -Be $true
        ($result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 16 }).PSObject.Properties.Name |
            Should -Not -Contain 'experimental'
    }

    It 'broadcasts to every matching combination for a partial-key include rule' {
        $rules = @([pscustomobject]@{ node = 18; tag = 'stable' })
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 3
        ($result | Where-Object { $_.node -eq 18 } | ForEach-Object { $_.tag }) | Should -Be @('stable', 'stable')
    }

    It 'appends a brand-new combination when the rule does not match any existing combination' {
        $rules = @([pscustomobject]@{ os = 'macos-latest'; node = 20 })
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 4
        $new = $result | Where-Object { $_.os -eq 'macos-latest' }
        $new.node | Should -Be 20
    }

    It 'appends a brand-new combination when the rule shares no keys with the matrix dimensions' {
        $rules = @([pscustomobject]@{ label = 'nightly' })
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 4
        ($result | Where-Object { $_.PSObject.Properties.Name -contains 'label' }).label | Should -Be 'nightly'
    }

    It 'lets a later include rule overwrite an earlier rule''s augmentation of the same combination' {
        $rules = @(
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 18; tag = 'a' }
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 18; tag = 'b' }
        )
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 3
        (($result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 18 }).tag) | Should -Be 'b'
    }

    It 'does not attach a rule requiring an unseen combination of base-key values; it appends a new job instead' {
        $rules = @([pscustomobject]@{ os = 'ubuntu-latest'; node = 99 })
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 4
        ($result | Where-Object { $_.node -eq 99 }).os | Should -Be 'ubuntu-latest'
    }

    It 'processes multiple include rules in order' {
        $rules = @(
            [pscustomobject]@{ os = 'ubuntu-latest'; node = 18; experimental = $true }
            [pscustomobject]@{ os = 'macos-latest'; node = 20 }
        )
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule $rules -DimensionKeys $Keys
        $result.Count | Should -Be 4
        (($result | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 18 }).experimental) | Should -Be $true
        (($result | Where-Object { $_.os -eq 'macos-latest' }).node) | Should -Be 20
    }

    It 'returns the input unchanged when there are no include rules' {
        $result = Merge-IncludedCombination -Combination $Combos -IncludeRule @() -DimensionKeys $Keys
        $result.Count | Should -Be 3
    }
}

Describe 'Assert-MatrixSize' {
    It 'does not throw when the count is within the limit' {
        { Assert-MatrixSize -Count 10 -MaxSize 256 } | Should -Not -Throw
    }

    It 'does not throw when the count exactly equals the limit' {
        { Assert-MatrixSize -Count 256 -MaxSize 256 } | Should -Not -Throw
    }

    It 'throws a meaningful error naming the count and the limit when exceeded' {
        { Assert-MatrixSize -Count 300 -MaxSize 256 } | Should -Throw '*300*256*'
    }

    It 'defaults the limit to 256 (the GitHub Actions matrix job limit) when not specified' {
        { Assert-MatrixSize -Count 257 } | Should -Throw '*256*'
        { Assert-MatrixSize -Count 256 } | Should -Not -Throw
    }
}

Describe 'New-EnvironmentMatrix' {
    It 'throws a meaningful error when the config has no matrix key' {
        $config = [pscustomobject]@{ include = @() }
        { New-EnvironmentMatrix -Config $config } | Should -Throw "*'matrix'*"
    }

    It 'builds a plain cartesian matrix with fail-fast defaulted to true and no max-parallel key' {
        $config = '{"matrix":{"os":["ubuntu-latest","windows-latest"],"node":[16,18]}}' | ConvertFrom-Json
        $strategy = New-EnvironmentMatrix -Config $config

        $strategy.'fail-fast' | Should -Be $true
        $strategy.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
        $strategy.matrix.include.Count | Should -Be 4
        $strategy.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $strategy.matrix.include[0].node | Should -Be 16
        $strategy.matrix.include[3].os | Should -Be 'windows-latest'
        $strategy.matrix.include[3].node | Should -Be 18
    }

    It 'applies exclude rules, include rules, fail-fast and max-parallel from config' {
        $configJson = @'
{
  "matrix": { "os": ["ubuntu-latest", "windows-latest"], "node": [16, 18] },
  "exclude": [ { "os": "windows-latest", "node": 16 } ],
  "include": [
    { "os": "ubuntu-latest", "node": 18, "experimental": true },
    { "os": "macos-latest", "node": 20 }
  ],
  "fail-fast": false,
  "max-parallel": 3
}
'@
        $config = $configJson | ConvertFrom-Json
        $strategy = New-EnvironmentMatrix -Config $config

        $strategy.'fail-fast' | Should -Be $false
        $strategy.'max-parallel' | Should -Be 3
        $strategy.matrix.include.Count | Should -Be 4
        $strategy.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $strategy.matrix.include[0].node | Should -Be 16
        $strategy.matrix.include[1].os | Should -Be 'ubuntu-latest'
        $strategy.matrix.include[1].node | Should -Be 18
        $strategy.matrix.include[1].experimental | Should -Be $true
        $strategy.matrix.include[2].os | Should -Be 'windows-latest'
        $strategy.matrix.include[2].node | Should -Be 18
        $strategy.matrix.include[3].os | Should -Be 'macos-latest'
        $strategy.matrix.include[3].node | Should -Be 20
    }

    It 'throws when the resulting matrix exceeds a configured max-size' {
        $configJson = '{"matrix":{"os":["a","b"],"node":[1,2,3]},"max-size":4}'
        $config = $configJson | ConvertFrom-Json
        { New-EnvironmentMatrix -Config $config } | Should -Throw '*exceeds the configured maximum of 4*'
    }
}

Describe 'Get-MatrixConfig' {
    BeforeAll {
        $script:TempConfigPath = Join-Path ([System.IO.Path]::GetTempPath()) "matrix-config-$(Get-Random).json"
    }

    AfterAll {
        Remove-Item -Path $TempConfigPath -ErrorAction SilentlyContinue
    }

    It 'throws a meaningful error when the file does not exist' {
        { Get-MatrixConfig -Path '/no/such/file.json' } | Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the file contains invalid JSON' {
        Set-Content -Path $TempConfigPath -Value '{ not valid json'
        { Get-MatrixConfig -Path $TempConfigPath } | Should -Throw '*Failed to parse JSON*'
    }

    It 'parses a valid config file into an object' {
        Set-Content -Path $TempConfigPath -Value '{"matrix":{"os":["ubuntu-latest"]}}'
        $config = Get-MatrixConfig -Path $TempConfigPath
        $config.matrix.os | Should -Be 'ubuntu-latest'
    }
}

Describe 'ConvertTo-MatrixJson' {
    It 'produces compact, parseable JSON matching the computed strategy' {
        $config = '{"matrix":{"os":["ubuntu-latest"]}}' | ConvertFrom-Json
        $json = ConvertTo-MatrixJson -Config $config -Compress
        $json | Should -Be '{"fail-fast":true,"matrix":{"include":[{"os":"ubuntu-latest"}]}}'
        $parsed = $json | ConvertFrom-Json
        $parsed.matrix.include[0].os | Should -Be 'ubuntu-latest'
    }
}
