#requires -Modules Pester

# Pester unit tests for the build-matrix generator.
#
# TDD note: each Describe block was written test-first (red) before the
# corresponding function in BuildMatrix.psm1 existed. The module is imported
# fresh so the tests always exercise the current source.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot 'BuildMatrix.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-CartesianProduct' {
    It 'produces the cross product of every dimension' {
        $dims = [ordered]@{
            os   = @('ubuntu', 'windows')
            node = @('18', '20')
        }
        $combos = Get-CartesianProduct -Dimensions $dims
        $combos.Count | Should -Be 4
    }

    It 'keeps dimension declaration order in each combination' {
        $dims = [ordered]@{ os = @('ubuntu'); node = @('20') }
        $combo = (Get-CartesianProduct -Dimensions $dims)[0]
        @($combo.Keys) | Should -Be @('os', 'node')
    }

    It 'returns a single empty combination when there are no dimensions' {
        $combos = Get-CartesianProduct -Dimensions ([ordered]@{})
        $combos.Count | Should -Be 1
        @($combos[0].Keys).Count | Should -Be 0
    }

    It 'collapses to nothing when a dimension has no values' {
        $dims = [ordered]@{ os = @('ubuntu'); node = @() }
        (Get-CartesianProduct -Dimensions $dims).Count | Should -Be 0
    }
}

Describe 'Remove-ExcludedCombinations' {
    It 'removes combinations that fully match an exclude entry' {
        $combos = Get-CartesianProduct -Dimensions ([ordered]@{
            os   = @('ubuntu', 'windows')
            node = @('18', '20')
        })
        $excludes = @( [ordered]@{ os = 'windows'; node = '18' } )
        $result = Remove-ExcludedCombinations -Combinations $combos -Excludes $excludes
        $result.Count | Should -Be 3
        ($result | Where-Object { $_.os -eq 'windows' -and $_.node -eq '18' }).Count | Should -Be 0
    }

    It 'treats a partial exclude entry as matching any superset' {
        $combos = Get-CartesianProduct -Dimensions ([ordered]@{
            os   = @('ubuntu', 'windows')
            node = @('18', '20')
        })
        # Excluding just os=windows should drop both windows rows.
        $excludes = @( [ordered]@{ os = 'windows' } )
        $result = Remove-ExcludedCombinations -Combinations $combos -Excludes $excludes
        $result.Count | Should -Be 2
    }

    It 'is a no-op when there are no excludes' {
        $combos = Get-CartesianProduct -Dimensions ([ordered]@{ os = @('a', 'b') })
        (Remove-ExcludedCombinations -Combinations $combos -Excludes @()).Count | Should -Be 2
    }
}

Describe 'Add-IncludedCombinations' {
    # Canonical example from the GitHub Actions documentation. Verifies the
    # full add-to-matching-original-combos / append-as-new-combo algorithm.
    It 'matches the GitHub Actions documented expansion' {
        $dims = [ordered]@{
            fruit  = @('apple', 'pear')
            animal = @('cat', 'dog')
        }
        $combos = Get-CartesianProduct -Dimensions $dims
        $includes = @(
            [ordered]@{ color = 'green' }
            [ordered]@{ color = 'pink'; animal = 'cat' }
            [ordered]@{ fruit = 'apple'; shape = 'circle' }
            [ordered]@{ fruit = 'banana' }
            [ordered]@{ fruit = 'banana'; animal = 'cat' }
        )
        $result = Add-IncludedCombinations -Combinations $combos -Includes $includes -DimensionKeys @('fruit', 'animal')

        $result.Count | Should -Be 6

        $apv = $result | Where-Object { $_.fruit -eq 'apple' -and $_.animal -eq 'cat' }
        $apv.color | Should -Be 'pink'
        $apv.shape | Should -Be 'circle'

        $adv = $result | Where-Object { $_.fruit -eq 'apple' -and $_.animal -eq 'dog' }
        $adv.color | Should -Be 'green'
        $adv.shape | Should -Be 'circle'

        $pcat = $result | Where-Object { $_.fruit -eq 'pear' -and $_.animal -eq 'cat' }
        $pcat.color | Should -Be 'pink'

        # The two banana entries are appended as standalone combinations.
        $bananas = @($result | Where-Object { $_.fruit -eq 'banana' })
        $bananas.Count | Should -Be 2
        @($bananas | Where-Object { -not $_.Contains('animal') }).Count | Should -Be 1
        @($bananas | Where-Object { $_.Contains('animal') -and $_.animal -eq 'cat' }).Count | Should -Be 1
    }

    It 'appends an include with no matching dimension keys to every combination' {
        $combos = Get-CartesianProduct -Dimensions ([ordered]@{ os = @('a', 'b') })
        $result = Add-IncludedCombinations -Combinations $combos -Includes @([ordered]@{ flag = 'on' }) -DimensionKeys @('os')
        $result.Count | Should -Be 2
        ($result | Where-Object { $_.flag -eq 'on' }).Count | Should -Be 2
    }
}

Describe 'New-BuildMatrix (orchestrator)' {
    It 'builds a basic matrix with the right job count and strategy knobs' {
        $config = [pscustomobject]@{
            matrix      = [pscustomobject]@{ os = @('ubuntu', 'windows'); node = @('18', '20') }
            failFast    = $false
            maxParallel = 3
        }
        $m = New-BuildMatrix -Config $config
        $m.'job-count' | Should -Be 4
        $m.'fail-fast' | Should -Be $false
        $m.'max-parallel' | Should -Be 3
        $m.jobs.Count | Should -Be 4
    }

    It 'applies exclude then include in order' {
        $config = [pscustomobject]@{
            matrix = [pscustomobject]@{
                os      = @('ubuntu', 'windows', 'macos')
                node    = @('18', '20')
                exclude = @([pscustomobject]@{ os = 'macos'; node = '18' })
                include = @([pscustomobject]@{ os = 'ubuntu'; node = '20'; experimental = $true })
            }
        }
        $m = New-BuildMatrix -Config $config
        # 6 base - 1 excluded = 5 jobs (include merges into an existing combo).
        $m.'job-count' | Should -Be 5
        $exp = $m.jobs | Where-Object { $_.os -eq 'ubuntu' -and $_.node -eq '20' }
        $exp.experimental | Should -Be $true
    }

    It 'defaults fail-fast to true and max-parallel to null when unspecified' {
        $config = [pscustomobject]@{ matrix = [pscustomobject]@{ os = @('ubuntu') } }
        $m = New-BuildMatrix -Config $config
        $m.'fail-fast' | Should -Be $true
        $m.'max-parallel' | Should -Be $null
    }

    It 'throws a meaningful error when the matrix is missing' {
        $config = [pscustomobject]@{ failFast = $true }
        { New-BuildMatrix -Config $config } | Should -Throw '*matrix*'
    }

    It 'throws a meaningful error when there are no dimensions and no include' {
        $config = [pscustomobject]@{ matrix = [pscustomobject]@{} }
        { New-BuildMatrix -Config $config } | Should -Throw '*at least one*'
    }

    It 'enforces the maximum matrix size with a meaningful error' {
        $config = [pscustomobject]@{
            matrix  = [pscustomobject]@{ a = @(1, 2, 3); b = @(1, 2, 3) }
            maxSize = 4
        }
        { New-BuildMatrix -Config $config } | Should -Throw '*exceeds*maximum*'
    }

    It 'allows a matrix exactly at the maximum size' {
        $config = [pscustomobject]@{
            matrix  = [pscustomobject]@{ a = @(1, 2); b = @(1, 2) }
            maxSize = 4
        }
        (New-BuildMatrix -Config $config).'job-count' | Should -Be 4
    }
}

Describe 'ConvertFrom-MatrixConfigJson' {
    It 'parses a JSON config and preserves dimension order' {
        $json = '{ "matrix": { "os": ["ubuntu","windows"], "node": ["20"] }, "failFast": false }'
        $config = ConvertFrom-MatrixConfigJson -Json $json
        $m = New-BuildMatrix -Config $config
        $m.'job-count' | Should -Be 2
        $m.'fail-fast' | Should -Be $false
    }

    It 'throws a meaningful error on invalid JSON' {
        { ConvertFrom-MatrixConfigJson -Json '{ not valid' } | Should -Throw '*JSON*'
    }
}

Describe 'ConvertTo-MatrixJson (output contract)' {
    It 'emits GitHub-style kebab-case strategy keys' {
        $config = [pscustomobject]@{
            matrix      = [pscustomobject]@{ os = @('ubuntu') }
            failFast    = $false
            maxParallel = 2
        }
        $json = New-BuildMatrix -Config $config | ConvertTo-MatrixJson
        $obj = $json | ConvertFrom-Json
        $obj.'fail-fast' | Should -Be $false
        $obj.'max-parallel' | Should -Be 2
        $obj.matrix.os | Should -Be @('ubuntu')
        $obj.'job-count' | Should -Be 1
    }
}
