<#
    Unit tests for the environment matrix generator.

    Testing policy for this task: these tests are NOT run directly on the
    development host. They are executed exclusively inside the containerized
    GitHub Actions job via `act push` (see .github/workflows/environment-matrix-generator.yml,
    step "Run unit tests"). This file is written test-first (red), before
    MatrixFunctions.ps1/EnvironmentMatrixGenerator.ps1 existed, following
    red/green TDD -- the implementation was added afterwards to satisfy it.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'MatrixFunctions.ps1')

    $script:FixturesPath = Join-Path $PSScriptRoot 'fixtures'

    function Get-Fixture([string]$Name) {
        Get-Content -Path (Join-Path $script:FixturesPath $Name) -Raw | ConvertFrom-Json
    }
}

Describe 'Get-MatrixCombinations' {
    It 'produces the cartesian product of all dimensions' {
        $dims = [ordered]@{ os = @('a', 'b'); version = @('1', '2') }
        $result = Get-MatrixCombinations -Dimensions $dims

        $result.Count | Should -Be 4
        $result[0].os | Should -Be 'a'
        $result[0].version | Should -Be '1'
        $result[1].os | Should -Be 'a'
        $result[1].version | Should -Be '2'
        $result[2].os | Should -Be 'b'
        $result[2].version | Should -Be '1'
        $result[3].os | Should -Be 'b'
        $result[3].version | Should -Be '2'
    }

    It 'preserves dimension key order in each combination' {
        $dims = [ordered]@{ os = @('a'); version = @('1'); flags = @('x') }
        $result = Get-MatrixCombinations -Dimensions $dims

        @($result[0].Keys) | Should -Be @('os', 'version', 'flags')
    }

    It 'returns a single empty combination when there are no dimensions' {
        $dims = [ordered]@{}
        $result = Get-MatrixCombinations -Dimensions $dims

        $result.Count | Should -Be 1
        @($result[0].Keys).Count | Should -Be 0
    }
}

Describe 'Remove-ExcludedCombinations' {
    BeforeEach {
        $script:combos = Get-MatrixCombinations -Dimensions ([ordered]@{ os = @('ubuntu-latest', 'macos-latest'); version = @('18', '20') })
    }

    It 'removes combinations that match every key in an exclude rule' {
        $rule = [pscustomobject]@{ os = 'macos-latest'; version = '18' }
        $result = Remove-ExcludedCombinations -Combinations $combos -ExcludeRules @($rule)

        $result.Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'macos-latest' -and $_.version -eq '18' }).Count | Should -Be 0
    }

    It 'treats an exclude rule as a wildcard on keys it does not mention' {
        $rule = [pscustomobject]@{ os = 'macos-latest' }
        $result = Remove-ExcludedCombinations -Combinations $combos -ExcludeRules @($rule)

        $result.Count | Should -Be 2
        ($result | Where-Object { $_.os -eq 'macos-latest' }).Count | Should -Be 0
    }

    It 'returns all combinations unchanged when no exclude rules are given' {
        $result = Remove-ExcludedCombinations -Combinations $combos -ExcludeRules @()
        $result.Count | Should -Be 4
    }
}

Describe 'Merge-IncludeRules' {
    BeforeEach {
        $script:combos = Get-MatrixCombinations -Dimensions ([ordered]@{ os = @('ubuntu-latest', 'windows-latest'); version = @('18') })
        $script:dimensionKeys = @('os', 'version')
    }

    It 'adds extra keys to every existing combination that matches the include rule' {
        $rule = [pscustomobject]@{ os = 'ubuntu-latest'; version = '18'; flags = 'experimental' }
        $result = Merge-IncludeRules -Combinations $combos -IncludeRules @($rule) -DimensionKeys $dimensionKeys

        $result.Count | Should -Be 2
        ($result | Where-Object { $_.os -eq 'ubuntu-latest' }).flags | Should -Be 'experimental'
    }

    It 'adds a new combination when the include rule matches nothing existing' {
        $rule = [pscustomobject]@{ os = 'macos-latest'; version = '20'; flags = 'beta' }
        $result = Merge-IncludeRules -Combinations $combos -IncludeRules @($rule) -DimensionKeys $dimensionKeys

        $result.Count | Should -Be 3
        $newEntry = $result | Where-Object { $_.os -eq 'macos-latest' }
        $newEntry.version | Should -Be '20'
        $newEntry.flags | Should -Be 'beta'
    }

    It 'applies an include rule to every matching combination when it matches several' {
        $rule = [pscustomobject]@{ os = 'ubuntu-latest'; extra = 'yes' }
        $result = Merge-IncludeRules -Combinations $combos -IncludeRules @($rule) -DimensionKeys $dimensionKeys

        $result.Count | Should -Be 2
        ($result | Where-Object { $_.os -eq 'ubuntu-latest' }).extra | Should -Be 'yes'
    }
}

Describe 'New-BuildMatrix' {
    It 'builds the full cartesian matrix for a basic config' {
        $config = Get-Fixture 'basic-config.json'
        $matrix = New-BuildMatrix -Config $config

        $matrix.strategy.'fail-fast' | Should -Be $true
        $matrix.strategy.'max-parallel' | Should -Be 2
        $matrix.strategy.matrix.include.Count | Should -Be 4
        $matrix.strategy.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $matrix.strategy.matrix.include[0].version | Should -Be '18'
        $matrix.strategy.matrix.include[3].os | Should -Be 'windows-latest'
        $matrix.strategy.matrix.include[3].version | Should -Be '20'
    }

    It 'applies exclude rules and honors an explicit failFast=false' {
        $config = Get-Fixture 'excludes-config.json'
        $matrix = New-BuildMatrix -Config $config

        $matrix.strategy.'fail-fast' | Should -Be $false
        $matrix.strategy.matrix.include.Count | Should -Be 5
        ($matrix.strategy.matrix.include | Where-Object { $_.os -eq 'macos-latest' -and $_.version -eq '18' }).Count | Should -Be 0
    }

    It 'applies include rules, merging into matches and appending new entries' {
        $config = Get-Fixture 'includes-config.json'
        $matrix = New-BuildMatrix -Config $config

        $matrix.strategy.matrix.include.Count | Should -Be 3

        $ubuntu = $matrix.strategy.matrix.include | Where-Object { $_.os -eq 'ubuntu-latest' }
        $ubuntu.flags | Should -Be 'experimental'

        $windows = $matrix.strategy.matrix.include | Where-Object { $_.os -eq 'windows-latest' }
        $windows.PSObject.Properties.Name | Should -Not -Contain 'flags'

        $macos = $matrix.strategy.matrix.include | Where-Object { $_.os -eq 'macos-latest' }
        $macos.version | Should -Be '20'
        $macos.flags | Should -Be 'beta'
    }

    It 'defaults fail-fast to true and omits max-parallel when not specified' {
        $config = Get-Fixture 'defaults-config.json'
        $matrix = New-BuildMatrix -Config $config

        $matrix.strategy.'fail-fast' | Should -Be $true
        $matrix.strategy.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
        $matrix.strategy.matrix.include.Count | Should -Be 1
    }

    It 'throws a meaningful error when the matrix would exceed maxMatrixSize' {
        $config = Get-Fixture 'exceeds-max-config.json'

        { New-BuildMatrix -Config $config } | Should -Throw -ExpectedMessage '*exceeding the maximum allowed size of 5*'
    }

    It 'throws a meaningful error when the matrix definition is empty' {
        $config = Get-Fixture 'invalid-config.json'

        { New-BuildMatrix -Config $config } | Should -Throw -ExpectedMessage "*non-empty 'matrix' object*"
    }

    It 'throws a meaningful error when the config has no matrix key at all' {
        $config = [pscustomobject]@{ someOtherKey = 'value' }

        { New-BuildMatrix -Config $config } | Should -Throw -ExpectedMessage "*non-empty 'matrix' object*"
    }

    It 'rejects a non-positive maxParallel value' {
        $config = Get-Fixture 'basic-config.json'
        $config.maxParallel = 0

        { New-BuildMatrix -Config $config } | Should -Throw -ExpectedMessage '*maxParallel*'
    }
}

Describe 'EnvironmentMatrixGenerator.ps1 (CLI end-to-end)' {
    BeforeAll {
        $script:cliPath = Join-Path $PSScriptRoot 'EnvironmentMatrixGenerator.ps1'
    }

    It 'prints valid, parseable matrix JSON to stdout for a config file' {
        $configPath = Join-Path $script:FixturesPath 'basic-config.json'
        $output = & $script:cliPath -ConfigPath $configPath
        $parsed = $output | ConvertFrom-Json

        $parsed.strategy.matrix.include.Count | Should -Be 4
        $parsed.strategy.'max-parallel' | Should -Be 2
    }

    It 'throws a clear error when the config file does not exist' {
        { & $script:cliPath -ConfigPath (Join-Path $script:FixturesPath 'does-not-exist.json') } | Should -Throw -ExpectedMessage '*Configuration file not found*'
    }

    It 'writes the matrix JSON to an output file when -OutputPath is given' {
        $configPath = Join-Path $script:FixturesPath 'basic-config.json'
        $outFile = Join-Path ([System.IO.Path]::GetTempPath()) "matrix-$([guid]::NewGuid()).json"
        try {
            & $script:cliPath -ConfigPath $configPath -OutputPath $outFile | Out-Null
            Test-Path $outFile | Should -Be $true
            $parsed = Get-Content -Path $outFile -Raw | ConvertFrom-Json
            $parsed.strategy.matrix.include.Count | Should -Be 4
        } finally {
            Remove-Item -Path $outFile -ErrorAction SilentlyContinue
        }
    }
}
