<#
.SYNOPSIS
    Unit tests for the Environment Matrix Generator (TDD suite).

.DESCRIPTION
    Built with red/green TDD. Each Describe block below corresponds to one
    red/green cycle, in the order the functionality was developed:

      Cycle 1: Expand-MatrixAxes        - cartesian product of the config axes
      Cycle 2: exclude rules            - partial-match removal (GHA semantics)
      Cycle 3: include rules            - merge-or-append (GHA-like semantics)
      Cycle 4: matrix size validation   - reject matrices over the size cap
      Cycle 5: New-BuildMatrixStrategy  - full strategy object assembly
      Cycle 6: config validation errors - meaningful messages for bad input
      Cycle 7: CLI entry script         - end-to-end JSON output + exit codes
#>

BeforeAll {
    # Dot-source the implementation under test.
    . (Join-Path $PSScriptRoot '..' 'src' 'MatrixGenerator.ps1')
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Describe 'Expand-MatrixAxes (cycle 1: cartesian product)' {
    It 'expands two axes into their cartesian product, first axis outermost' {
        $axes = [ordered]@{
            os      = @('ubuntu-22.04', 'windows-2022')
            version = @('3.11', '3.12')
        }

        $combos = Expand-MatrixAxes -Axes $axes

        $combos.Count | Should -Be 4
        # Order matters for deterministic JSON output: os varies slowest.
        $combos[0].os | Should -Be 'ubuntu-22.04'
        $combos[0].version | Should -Be '3.11'
        $combos[1].os | Should -Be 'ubuntu-22.04'
        $combos[1].version | Should -Be '3.12'
        $combos[2].os | Should -Be 'windows-2022'
        $combos[2].version | Should -Be '3.11'
        $combos[3].os | Should -Be 'windows-2022'
        $combos[3].version | Should -Be '3.12'
    }

    It 'expands three axes (os x version x flags)' {
        $axes = [ordered]@{
            os      = @('ubuntu-22.04')
            version = @('3.11', '3.12')
            flags   = @('standard', 'experimental')
        }

        $combos = Expand-MatrixAxes -Axes $axes

        $combos.Count | Should -Be 4
        $combos[0].flags | Should -Be 'standard'
        $combos[1].flags | Should -Be 'experimental'
        $combos[3].version | Should -Be '3.12'
    }

    It 'handles a single-value single axis' {
        $combos = Expand-MatrixAxes -Axes ([ordered]@{ os = @('ubuntu-22.04') })
        $combos.Count | Should -Be 1
        $combos[0].os | Should -Be 'ubuntu-22.04'
    }
}

Describe 'Remove-ExcludedCombination (cycle 2: exclude rules)' {
    BeforeEach {
        $script:combos = Expand-MatrixAxes -Axes ([ordered]@{
                os      = @('ubuntu-22.04', 'macos-14')
                version = @('3.11', '3.12')
            })
    }

    It 'removes a combination matched exactly by an exclude rule' {
        $result = Remove-ExcludedCombination -Combinations $combos -ExcludeRules @(
            [ordered]@{ os = 'macos-14'; version = '3.11' }
        )

        $result.Count | Should -Be 3
        # macos-14 + 3.11 must be gone; macos-14 + 3.12 must survive.
        # (@() wrapping: Where-Object unwraps single results to the bare
        # hashtable, whose .Count would be its key count.)
        @($result | Where-Object { $_.os -eq 'macos-14' }).Count | Should -Be 1
        @($result | Where-Object { $_.os -eq 'macos-14' })[0].version | Should -Be '3.12'
    }

    It 'supports partial-match excludes (GHA semantics: all rule keys must match)' {
        # Excluding by os alone removes every macos combination.
        $result = Remove-ExcludedCombination -Combinations $combos -ExcludeRules @(
            [ordered]@{ os = 'macos-14' }
        )

        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.os | Should -Be 'ubuntu-22.04' }
    }

    It 'leaves the matrix untouched when no rule matches' {
        $result = Remove-ExcludedCombination -Combinations $combos -ExcludeRules @(
            [ordered]@{ os = 'windows-2022' }
        )
        $result.Count | Should -Be 4
    }

    It 'returns the matrix unchanged for an empty rule list' {
        $result = Remove-ExcludedCombination -Combinations $combos -ExcludeRules @()
        $result.Count | Should -Be 4
    }
}

Describe 'Add-IncludedCombination (cycle 3: include rules)' {
    BeforeEach {
        $script:axisNames = @('os', 'version')
        $script:combos = Expand-MatrixAxes -Axes ([ordered]@{
                os      = @('ubuntu-22.04', 'macos-14')
                version = @('3.11')
            })
    }

    It 'merges extra keys into combinations matched on axis keys' {
        $result = Add-IncludedCombination -Combinations $combos -IncludeRules @(
            [ordered]@{ os = 'ubuntu-22.04'; coverage = $true }
        ) -AxisNames $axisNames

        $result.Count | Should -Be 2
        @($result | Where-Object { $_.os -eq 'ubuntu-22.04' })[0].coverage | Should -BeTrue
        @($result | Where-Object { $_.os -eq 'macos-14' })[0].Contains('coverage') | Should -BeFalse
    }

    It 'appends an include as a new combination when no axis values match' {
        $result = Add-IncludedCombination -Combinations $combos -IncludeRules @(
            [ordered]@{ os = 'windows-2022'; version = '3.13' }
        ) -AxisNames $axisNames

        $result.Count | Should -Be 3
        $result[2].os | Should -Be 'windows-2022'
        $result[2].version | Should -Be '3.13'
    }

    It 'merges an include with only non-axis keys into every combination' {
        $result = Add-IncludedCombination -Combinations $combos -IncludeRules @(
            [ordered]@{ experimental = 'false' }
        ) -AxisNames $axisNames

        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.experimental | Should -Be 'false' }
    }

    It 'returns the matrix unchanged for an empty rule list' {
        $result = Add-IncludedCombination -Combinations $combos -IncludeRules @() -AxisNames $axisNames
        $result.Count | Should -Be 2
    }
}

Describe 'Test-MatrixSize (cycle 4: size validation)' {
    It 'passes when the matrix is within the limit' {
        { Test-MatrixSize -Count 4 -MaxSize 10 } | Should -Not -Throw
    }

    It 'passes when the matrix is exactly at the limit' {
        { Test-MatrixSize -Count 10 -MaxSize 10 } | Should -Not -Throw
    }

    It 'throws a meaningful error when the matrix exceeds the limit' {
        { Test-MatrixSize -Count 300 -MaxSize 256 } |
            Should -Throw '*300*exceeds the maximum allowed size*256*'
    }
}

Describe 'New-BuildMatrixStrategy (cycle 5: strategy assembly)' {
    It 'builds the full strategy object from a minimal config' {
        $config = '{ "os": ["ubuntu-22.04"], "languageVersions": ["3.12"] }' | ConvertFrom-Json

        $strategy = New-BuildMatrixStrategy -Config $config

        $strategy['fail-fast'] | Should -BeTrue          # default: true (GHA default)
        $strategy.Contains('max-parallel') | Should -BeFalse  # omitted unless configured
        $strategy.matrix.include.Count | Should -Be 1
        $strategy.matrix.include[0].os | Should -Be 'ubuntu-22.04'
        $strategy.matrix.include[0].version | Should -Be '3.12'
    }

    It 'honors failFast, maxParallel, featureFlags, include and exclude' {
        $config = @'
{
  "os": ["ubuntu-22.04", "macos-14"],
  "languageVersions": ["3.12"],
  "featureFlags": ["standard", "experimental"],
  "exclude": [ { "os": "macos-14", "flags": "experimental" } ],
  "include": [
    { "os": "ubuntu-22.04", "flags": "experimental", "coverage": true },
    { "os": "windows-2022", "version": "3.13", "flags": "standard" }
  ],
  "failFast": false,
  "maxParallel": 2
}
'@ | ConvertFrom-Json

        $strategy = New-BuildMatrixStrategy -Config $config

        $strategy['fail-fast'] | Should -BeFalse
        $strategy['max-parallel'] | Should -Be 2
        $include = $strategy.matrix.include
        $include.Count | Should -Be 4
        # Deterministic order: cartesian order, includes appended last.
        $include[0].os | Should -Be 'ubuntu-22.04'; $include[0].flags | Should -Be 'standard'
        $include[1].flags | Should -Be 'experimental'; $include[1].coverage | Should -BeTrue
        $include[2].os | Should -Be 'macos-14'; $include[2].flags | Should -Be 'standard'
        $include[3].os | Should -Be 'windows-2022'; $include[3].version | Should -Be '3.13'
    }

    It 'enforces maxMatrixSize from the config' {
        $config = @'
{
  "os": ["a", "b", "c"],
  "languageVersions": ["1", "2", "3"],
  "maxMatrixSize": 8
}
'@ | ConvertFrom-Json

        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw '*9*exceeds the maximum allowed size*8*'
    }

    It 'defaults maxMatrixSize to 256 (the GitHub Actions limit)' {
        # 2 os x 130 versions = 260 > 256 -> must throw with the default cap.
        $versions = @(1..130 | ForEach-Object { "$_" })
        $config = [pscustomobject]@{ os = @('a', 'b'); languageVersions = $versions }

        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw '*260*exceeds the maximum allowed size*256*'
    }
}

Describe 'New-BuildMatrixStrategy (cycle 6: config validation errors)' {
    It 'rejects a config without a non-empty os array' {
        $config = '{ "languageVersions": ["3.12"] }' | ConvertFrom-Json
        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw "*must include a non-empty 'os' array*"
    }

    It 'rejects a config without a non-empty languageVersions array' {
        $config = '{ "os": ["ubuntu-22.04"], "languageVersions": [] }' | ConvertFrom-Json
        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw "*must include a non-empty 'languageVersions' array*"
    }

    It 'rejects a non-positive maxParallel' {
        $config = '{ "os": ["a"], "languageVersions": ["1"], "maxParallel": 0 }' | ConvertFrom-Json
        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw "*'maxParallel' must be a positive integer*"
    }

    It 'rejects a non-positive maxMatrixSize' {
        $config = '{ "os": ["a"], "languageVersions": ["1"], "maxMatrixSize": -5 }' | ConvertFrom-Json
        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw "*'maxMatrixSize' must be a positive integer*"
    }

    It 'rejects a matrix where excludes removed every combination' {
        $config = @'
{
  "os": ["ubuntu-22.04"],
  "languageVersions": ["3.12"],
  "exclude": [ { "os": "ubuntu-22.04" } ]
}
'@ | ConvertFrom-Json
        { New-BuildMatrixStrategy -Config $config } |
            Should -Throw '*matrix is empty*exclude*'
    }
}

Describe 'Invoke-MatrixGenerator.ps1 (cycle 7: CLI entry script)' {
    BeforeAll {
        $script:cli = Join-Path $RepoRoot 'Invoke-MatrixGenerator.ps1'

        # Runs the CLI in a child pwsh process so exit codes are observable.
        function Invoke-Cli {
            param([string[]]$Arguments)
            $stdout = & pwsh -NoProfile -File $script:cli @Arguments 2>$null
            [pscustomobject]@{ StdOut = ($stdout -join "`n"); ExitCode = $LASTEXITCODE }
        }
    }

    It 'emits the exact expected compressed JSON for the case1 fixture' {
        $result = Invoke-Cli @('-ConfigPath', (Join-Path $RepoRoot 'fixtures/case1-config.json'))
        $expected = (Get-Content (Join-Path $RepoRoot 'fixtures/case1-expected.json') -Raw).Trim()

        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Be $expected
    }

    It 'emits the exact expected JSON for the case2 fixture (include/exclude/flags)' {
        $result = Invoke-Cli @('-ConfigPath', (Join-Path $RepoRoot 'fixtures/case2-config.json'))
        $expected = (Get-Content (Join-Path $RepoRoot 'fixtures/case2-expected.json') -Raw).Trim()

        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Be $expected
    }

    It 'writes the JSON to -OutputPath as well as stdout' {
        $outFile = Join-Path $TestDrive 'matrix.json'
        $result = Invoke-Cli @('-ConfigPath', (Join-Path $RepoRoot 'fixtures/case1-config.json'), '-OutputPath', $outFile)

        $result.ExitCode | Should -Be 0
        (Get-Content $outFile -Raw).Trim() |
            Should -Be (Get-Content (Join-Path $RepoRoot 'fixtures/case1-expected.json') -Raw).Trim()
    }

    It 'exits 1 with a meaningful error for a missing config file' {
        $result = Invoke-Cli @('-ConfigPath', (Join-Path $TestDrive 'does-not-exist.json'))
        $result.ExitCode | Should -Be 1
    }

    It 'exits 1 with a meaningful error for malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{ not valid json !'
        $result = Invoke-Cli @('-ConfigPath', $bad)
        $result.ExitCode | Should -Be 1
    }

    It 'exits 1 when the matrix exceeds maxMatrixSize' {
        $result = Invoke-Cli @('-ConfigPath', (Join-Path $RepoRoot 'fixtures/oversize-config.json'))
        $result.ExitCode | Should -Be 1
    }
}
