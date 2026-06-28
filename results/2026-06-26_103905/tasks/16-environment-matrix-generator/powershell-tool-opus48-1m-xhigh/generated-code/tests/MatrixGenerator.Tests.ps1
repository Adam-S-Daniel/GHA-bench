#requires -Module Pester

# TDD suite for the environment build-matrix generator.
#
# Red/green cycle 1: the most fundamental behaviour is expanding a set of
# named axes into the full cartesian product of combinations. We write this
# expectation first; the module + function do not exist yet, so this test is
# RED until Get-MatrixCombinations is implemented.

BeforeAll {
    # Resolve the module relative to this test file so the suite is runnable
    # from any working directory (locally and inside the CI container).
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'MatrixGenerator.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-MatrixCombinations - cartesian product' {
    It 'expands two axes into every combination, preserving axis order' {
        $matrix = [ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        }

        $result = Get-MatrixCombinations -Matrix $matrix

        # 2 * 2 = 4 combinations.
        $result.Count | Should -Be 4

        # Each combination is a hashtable/ordered dict carrying one value per axis.
        $result[0].os   | Should -Be 'ubuntu-latest'
        $result[0].node | Should -Be '18'
        $result[3].os   | Should -Be 'windows-latest'
        $result[3].node | Should -Be '20'
    }

    It 'expands three axes (os x language x feature)' {
        $matrix = [ordered]@{
            os      = @('ubuntu-latest', 'macos-latest')
            python  = @('3.11', '3.12', '3.13')
            feature = @('minimal', 'full')
        }

        $result = Get-MatrixCombinations -Matrix $matrix

        # 2 * 3 * 2 = 12 combinations.
        $result.Count | Should -Be 12
    }

    It 'returns a single empty combination when there are no axes' {
        $result = @(Get-MatrixCombinations -Matrix ([ordered]@{}))
        $result.Count | Should -Be 1
        $result[0].Keys.Count | Should -Be 0
    }
}

# Red/green cycle 2: GitHub Actions "exclude" entries remove any combination
# that is a *partial* match for the exclude object (every key in the exclude
# must match the combination).
Describe 'Remove-ExcludedCombinations' {
    BeforeEach {
        $script:combos = Get-MatrixCombinations -Matrix ([ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        })
    }

    It 'removes a single fully-specified combination' {
        $exclude = @( [ordered]@{ os = 'windows-latest'; node = '18' } )
        $result = @(Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude)

        $result.Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }).Count | Should -Be 0
    }

    It 'removes every combination matching a partial exclude' {
        $exclude = @( [ordered]@{ node = '18' } )
        $result = @(Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude)

        # Both node=18 combos drop; both node=20 combos remain.
        $result.Count | Should -Be 2
        ($result | Where-Object { $_.node -eq '18' }).Count | Should -Be 0
    }

    It 'is a no-op when no combination matches the exclude' {
        $exclude = @( [ordered]@{ os = 'nonexistent' } )
        $result = @(Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude)
        $result.Count | Should -Be 4
    }

    It 'applies multiple exclude entries' {
        $exclude = @(
            [ordered]@{ os = 'windows-latest'; node = '18' }
            [ordered]@{ os = 'ubuntu-latest';  node = '20' }
        )
        $result = @(Remove-ExcludedCombinations -Combinations $script:combos -Exclude $exclude)
        $result.Count | Should -Be 2
    }
}

# Red/green cycle 3: the GitHub Actions "include" algorithm. This is the most
# intricate part. The behaviour is taken directly from GitHub's documentation:
#
#   For each object in the include list, its key:value pairs are added to each
#   matrix combination provided none of the keys that are *original matrix axes*
#   would be overwritten. If an include cannot be merged into any existing
#   combination, it is appended as a brand-new combination. Original axis values
#   are never overwritten; added (non-axis) values can be overwritten.
Describe 'Add-IncludedCombinations' {
    BeforeEach {
        $script:base = Get-MatrixCombinations -Matrix ([ordered]@{
            os   = @('ubuntu-latest', 'windows-latest')
            node = @('18', '20')
        })
        $script:originalKeys = @('os', 'node')
    }

    It 'adds extra keys to every combination when the include has no axis keys' {
        $include = @( [ordered]@{ coverage = 'true' } )
        $result = @(Add-IncludedCombinations -Combinations $script:base -Include $include -OriginalKeys $script:originalKeys)

        $result.Count | Should -Be 4
        ($result | Where-Object { $_.coverage -eq 'true' }).Count | Should -Be 4
    }

    It 'adds extra keys only to combinations matching the include axis constraint' {
        $include = @( [ordered]@{ os = 'ubuntu-latest'; experimental = 'true' } )
        $result = @(Add-IncludedCombinations -Combinations $script:base -Include $include -OriginalKeys $script:originalKeys)

        $result.Count | Should -Be 4
        $ubuntu = @($result | Where-Object { $_.os -eq 'ubuntu-latest' })
        $ubuntu.Count | Should -Be 2
        ($ubuntu | Where-Object { $_.experimental -eq 'true' }).Count | Should -Be 2
        # Windows rows are untouched and have no 'experimental' key.
        ($result | Where-Object { $_.os -eq 'windows-latest' -and $_.Contains('experimental') }).Count | Should -Be 0
    }

    It 'appends a new combination when the include matches nothing' {
        $include = @( [ordered]@{ os = 'macos-latest'; node = '22' } )
        $result = @(Add-IncludedCombinations -Combinations $script:base -Include $include -OriginalKeys $script:originalKeys)

        $result.Count | Should -Be 5
        $result[4].os   | Should -Be 'macos-latest'
        $result[4].node | Should -Be '22'
    }

    It 'reproduces the canonical GitHub fruit/animal include example exactly' {
        # https://docs.github.com/actions - matrix include documentation example.
        $base = Get-MatrixCombinations -Matrix ([ordered]@{
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

        $result = @(Add-IncludedCombinations -Combinations $base -Include $include -OriginalKeys @('fruit', 'animal'))

        $result.Count | Should -Be 6

        # {apple, cat}  -> color pink (overwritten from green), shape circle
        $r0 = $result[0]
        $r0.fruit | Should -Be 'apple'; $r0.animal | Should -Be 'cat'
        $r0.color | Should -Be 'pink'; $r0.shape  | Should -Be 'circle'

        # {apple, dog}  -> color green, shape circle
        $r1 = $result[1]
        $r1.fruit | Should -Be 'apple'; $r1.animal | Should -Be 'dog'
        $r1.color | Should -Be 'green'; $r1.shape  | Should -Be 'circle'

        # {pear, cat}   -> color pink
        $r2 = $result[2]
        $r2.fruit | Should -Be 'pear'; $r2.animal | Should -Be 'cat'
        $r2.color | Should -Be 'pink'; $r2.Contains('shape') | Should -BeFalse

        # {pear, dog}   -> color green
        $r3 = $result[3]
        $r3.color | Should -Be 'green'; $r3.Contains('shape') | Should -BeFalse

        # Two appended banana combinations (the includes that matched nothing).
        $r4 = $result[4]
        $r4.fruit | Should -Be 'banana'; $r4.Contains('animal') | Should -BeFalse
        $r5 = $result[5]
        $r5.fruit | Should -Be 'banana'; $r5.animal | Should -Be 'cat'
    }

    It 'does not merge a later include into combinations created by an earlier include' {
        # Earlier include creates a new {os=macos} combination; a later include
        # constrained on os=macos must NOT merge into it (it appends instead).
        $include = @(
            [ordered]@{ os = 'macos-latest'; node = '22' }
            [ordered]@{ os = 'macos-latest'; extra = 'yes' }
        )
        $result = @(Add-IncludedCombinations -Combinations $script:base -Include $include -OriginalKeys $script:originalKeys)

        $result.Count | Should -Be 6
        # The first appended combo stays free of 'extra'.
        ($result | Where-Object { $_.node -eq '22' -and $_.Contains('extra') }).Count | Should -Be 0
    }
}

# Red/green cycle 4 + 5: the New-BuildMatrix orchestrator ties expansion +
# exclude + include together, carries strategy options (max-parallel,
# fail-fast), counts combinations, and validates the size limit. It also
# defines the canonical output object that the CLI serialises to JSON.
Describe 'New-BuildMatrix - orchestration and output shape' {
    It 'produces a GitHub-ready matrix object from a full config' {
        $config = [ordered]@{
            matrix = [ordered]@{
                os      = @('ubuntu-latest', 'windows-latest', 'macos-latest')
                node    = @('18', '20')
                exclude = @( [ordered]@{ os = 'macos-latest'; node = '18' } )
                include = @( [ordered]@{ os = 'ubuntu-latest'; node = '20'; coverage = 'true' } )
            }
            maxParallel = 3
            failFast    = $false
            maxSize     = 50
        }

        $out = New-BuildMatrix -Config $config

        # 3*2 = 6, minus 1 excluded = 5; the include merges (does not add a row).
        $out.count | Should -Be 5
        $out.matrix.include.Count | Should -Be 5
        $out.'max-parallel' | Should -Be 3
        $out.'fail-fast'    | Should -Be $false
        $out.'max-size'     | Should -Be 50

        # The coverage flag landed on exactly the ubuntu/20 row.
        # NB: wrap the filter in @() before .Count — a lone OrderedDictionary's
        # .Count is its *key* count, not 1.
        $cov = @($out.matrix.include | Where-Object { $_.coverage -eq 'true' })
        $cov.Count   | Should -Be 1
        $cov[0].os   | Should -Be 'ubuntu-latest'
        $cov[0].node | Should -Be '20'
    }

    It 'defaults fail-fast to true and max-size to 256 when unspecified' {
        $config = [ordered]@{ matrix = [ordered]@{ os = @('ubuntu-latest') } }
        $out = New-BuildMatrix -Config $config
        $out.'fail-fast' | Should -Be $true
        $out.'max-size'  | Should -Be 256
        $out.count       | Should -Be 1
    }

    It 'treats an include-only matrix as one job per include entry' {
        $config = [ordered]@{
            matrix = [ordered]@{
                include = @(
                    [ordered]@{ os = 'ubuntu-latest'; node = '18' }
                    [ordered]@{ os = 'windows-latest'; node = '20' }
                )
            }
        }
        $out = New-BuildMatrix -Config $config
        $out.count | Should -Be 2
        $out.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $out.matrix.include[1].os | Should -Be 'windows-latest'
    }

    It 'accepts a config parsed from JSON (PSCustomObject)' {
        $json = @'
{
  "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "exclude": [ { "os": "windows-latest", "node": "18" } ]
  },
  "maxParallel": 2,
  "failFast": false
}
'@
        $config = $json | ConvertFrom-Json
        $out = New-BuildMatrix -Config $config
        $out.count | Should -Be 3
        $out.'max-parallel' | Should -Be 2
        $out.'fail-fast'    | Should -Be $false
    }

    It 'accepts kebab-case strategy keys (max-parallel / fail-fast / max-size)' {
        $json = @'
{ "matrix": { "os": ["ubuntu-latest"] }, "max-parallel": 7, "fail-fast": false, "max-size": 9 }
'@
        $out = New-BuildMatrix -Config ($json | ConvertFrom-Json)
        $out.'max-parallel' | Should -Be 7
        $out.'fail-fast'    | Should -Be $false
        $out.'max-size'     | Should -Be 9
    }
}

Describe 'New-BuildMatrix - validation and error handling' {
    It 'throws a meaningful error when the matrix exceeds max-size' {
        $config = [ordered]@{
            matrix  = [ordered]@{ os = @('a', 'b', 'c'); node = @('1', '2', '3') }
            maxSize = 5
        }
        # 3*3 = 9 > 5
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage '*exceeds the maximum*9*5*'
    }

    It 'does not throw when the matrix is exactly at max-size' {
        $config = [ordered]@{
            matrix  = [ordered]@{ os = @('a', 'b'); node = @('1', '2') }
            maxSize = 4
        }
        { New-BuildMatrix -Config $config } | Should -Not -Throw
    }

    It 'throws when config has no matrix section' {
        { New-BuildMatrix -Config ([ordered]@{ maxParallel = 2 }) } |
            Should -Throw -ExpectedMessage "*'matrix'*"
    }

    It 'throws when the matrix produces zero combinations' {
        { New-BuildMatrix -Config ([ordered]@{ matrix = [ordered]@{} }) } |
            Should -Throw -ExpectedMessage '*no combinations*'
    }

    It 'throws when max-size is not a positive integer' {
        $config = [ordered]@{ matrix = [ordered]@{ os = @('a') }; maxSize = 0 }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage '*max-size*positive*'
    }

    It 'throws when an axis value list is empty' {
        $config = [ordered]@{ matrix = [ordered]@{ os = @() } }
        { New-BuildMatrix -Config $config } |
            Should -Throw -ExpectedMessage "*'os'*empty*"
    }
}

Describe 'ConvertTo-BuildMatrixJson - serialisation' {
    It 'emits valid JSON that round-trips to the same structure' {
        $config = [ordered]@{
            matrix = [ordered]@{
                os   = @('ubuntu-latest', 'windows-latest')
                node = @('18', '20')
            }
            maxParallel = 4
            failFast    = $false
        }

        $json = ConvertTo-BuildMatrixJson -Config $config
        $json | Should -BeOfType [string]

        $parsed = $json | ConvertFrom-Json
        $parsed.count | Should -Be 4
        # 'include' must serialise as a JSON array even with multiple entries.
        @($parsed.matrix.include).Count | Should -Be 4
        $parsed.'max-parallel' | Should -Be 4
        $parsed.'fail-fast'    | Should -Be $false
    }

    It 'serialises a single-combination include as a JSON array (not an object)' {
        $config = [ordered]@{ matrix = [ordered]@{ os = @('ubuntu-latest') } }
        $json = ConvertTo-BuildMatrixJson -Config $config
        # The raw JSON for include must start with '[' so fromJSON() in GitHub
        # Actions sees a list of one job, not a single object.
        ($json | ConvertFrom-Json).matrix.include | Should -Not -BeNullOrEmpty
        $json -match '"include"\s*:\s*\[' | Should -BeTrue
    }
}
