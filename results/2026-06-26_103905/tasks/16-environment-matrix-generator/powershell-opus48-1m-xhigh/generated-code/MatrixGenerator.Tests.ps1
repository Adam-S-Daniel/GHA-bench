#requires -Modules Pester

# Pester 5 unit tests for the build-matrix generator.
# Methodology: each test was written RED first, then the minimum code added to
# MatrixGenerator.psm1 to make it GREEN. Configs are built the same way the real
# CLI builds them (via ConvertFrom-Json) so the tests exercise the production path.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot 'MatrixGenerator.psm1'
    Import-Module $script:ModulePath -Force

    # Helper: turn a JSON literal into the same PSCustomObject shape the CLI feeds
    # to New-BuildMatrix, so tests and production share one input path.
    function ConvertToConfig([string]$Json) {
        $Json | ConvertFrom-Json
    }

    # Combos in the resolved matrix are ordered dictionaries. Render one (and an
    # expected hashtable) to a stable, key-sorted "k=v;k=v" string so an exact
    # whole-combination comparison reads cleanly via Should -Be.
    function ComboString($Combo) {
        ($Combo.Keys | Sort-Object | ForEach-Object { "$_=$($Combo[$_])" }) -join ';'
    }
    function ExpectedString([hashtable]$Expected) {
        ($Expected.Keys | Sort-Object | ForEach-Object { "$_=$($Expected[$_])" }) -join ';'
    }
}

Describe 'New-BuildMatrix - cartesian product' {
    It 'produces the full cross product of two dimensions in declaration order' {
        $config = ConvertToConfig @'
{ "matrix": { "os": ["ubuntu-latest", "windows-latest"], "node": ["18", "20"] } }
'@
        $result = New-BuildMatrix -Config $config

        $result.size | Should -Be 4
        $combos = $result.matrix.include

        # First dimension varies slowest (matches GitHub Actions ordering).
        $combos[0].os   | Should -Be 'ubuntu-latest'; $combos[0].node | Should -Be '18'
        $combos[1].os   | Should -Be 'ubuntu-latest'; $combos[1].node | Should -Be '20'
        $combos[2].os   | Should -Be 'windows-latest'; $combos[2].node | Should -Be '18'
        $combos[3].os   | Should -Be 'windows-latest'; $combos[3].node | Should -Be '20'
    }
}

Describe 'New-BuildMatrix - exclude rules' {
    It 'removes combinations that fully match an exclude rule' {
        $config = ConvertToConfig @'
{ "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "exclude": [ { "os": "windows-latest", "node": "18" } ]
} }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 3
        # The windows-latest/18 pair must be gone; the windows-latest/20 stays.
        $combos = $result.matrix.include
        # @() forces an array so .Count is the match count, not an ordered-dict's key count.
        @($combos | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }).Count | Should -Be 0
        @($combos | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '20' }).Count | Should -Be 1
    }

    It 'treats an exclude rule as a partial match (one key is enough)' {
        $config = ConvertToConfig @'
{ "matrix": {
    "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
    "node": ["18", "20"],
    "exclude": [ { "os": "macos-latest" } ]
} }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 4
        @($result.matrix.include | Where-Object { $_.os -eq 'macos-latest' }).Count | Should -Be 0
    }
}

Describe 'New-BuildMatrix - include rules' {
    It 'extends a matching combination with extra properties (feature flags)' {
        $config = ConvertToConfig @'
{ "matrix": {
    "os": ["ubuntu-latest", "windows-latest"],
    "node": ["18", "20"],
    "include": [ { "os": "ubuntu-latest", "node": "20", "experimental": true } ]
} }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 4   # no new rows, just an added property
        $target = $result.matrix.include | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq '20' }
        $target.experimental | Should -BeTrue
        # Non-matching combos must NOT gain the property.
        $other = $result.matrix.include | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }
        $other.Contains('experimental') | Should -BeFalse
    }

    It 'adds a standalone combination when the include matches nothing' {
        $config = ConvertToConfig @'
{ "matrix": {
    "os": ["ubuntu-latest"],
    "node": ["18"],
    "include": [ { "os": "macos-latest", "node": "21", "experimental": true } ]
} }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 2
        $extra = $result.matrix.include | Where-Object { $_.os -eq 'macos-latest' }
        $extra.node | Should -Be '21'
        $extra.experimental | Should -BeTrue
    }

    It 'reproduces the canonical GitHub Actions include example exactly' {
        # https://docs.github.com/actions ... matrix include documented example.
        $config = ConvertToConfig @'
{ "matrix": {
    "fruit": ["apple", "pear"],
    "animal": ["cat", "dog"],
    "include": [
        { "color": "green" },
        { "color": "pink", "animal": "cat" },
        { "fruit": "apple", "shape": "circle" },
        { "fruit": "banana" },
        { "fruit": "banana", "animal": "cat" }
    ]
} }
'@
        $result = New-BuildMatrix -Config $config
        $c = $result.matrix.include
        $result.size | Should -Be 6

        ComboString $c[0] | Should -Be (ExpectedString @{ fruit='apple'; animal='cat'; color='pink';  shape='circle' })
        ComboString $c[1] | Should -Be (ExpectedString @{ fruit='apple'; animal='dog'; color='green'; shape='circle' })
        ComboString $c[2] | Should -Be (ExpectedString @{ fruit='pear';  animal='cat'; color='pink' })
        ComboString $c[3] | Should -Be (ExpectedString @{ fruit='pear';  animal='dog'; color='green' })
        ComboString $c[4] | Should -Be (ExpectedString @{ fruit='banana' })
        ComboString $c[5] | Should -Be (ExpectedString @{ fruit='banana'; animal='cat' })
    }

    It 'supports an include-only matrix (no base dimensions)' {
        $config = ConvertToConfig @'
{ "matrix": { "include": [
    { "os": "ubuntu-latest", "node": "18" },
    { "os": "windows-latest", "node": "20" }
] } }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 2
        $result.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $result.matrix.include[1].os | Should -Be 'windows-latest'
    }
}

Describe 'New-BuildMatrix - feature flags as a dimension' {
    It 'expands boolean feature flags across the product and preserves type' {
        $config = ConvertToConfig @'
{ "matrix": {
    "os": ["ubuntu-latest"],
    "experimental": [true, false]
} }
'@
        $result = New-BuildMatrix -Config $config
        $result.size | Should -Be 2
        $result.matrix.include[0].experimental | Should -BeOfType [bool]
        $result.matrix.include[0].experimental | Should -BeTrue
        $result.matrix.include[1].experimental | Should -BeFalse
    }
}

Describe 'New-BuildMatrix - strategy knobs' {
    It 'passes through max-parallel and fail-fast' {
        $config = ConvertToConfig @'
{ "matrix": { "os": ["ubuntu-latest", "windows-latest"] },
  "max-parallel": 2, "fail-fast": false }
'@
        $result = New-BuildMatrix -Config $config
        $result.'max-parallel' | Should -Be 2
        $result.'fail-fast' | Should -BeFalse
    }

    It 'defaults fail-fast to true and max-parallel to null when omitted' {
        $config = ConvertToConfig '{ "matrix": { "os": ["ubuntu-latest"] } }'
        $result = New-BuildMatrix -Config $config
        $result.'fail-fast' | Should -BeTrue
        $result.'max-parallel' | Should -BeNullOrEmpty
    }

    It 'rejects a non-positive max-parallel with a clear message' {
        $config = ConvertToConfig '{ "matrix": { "os": ["ubuntu-latest"] }, "max-parallel": 0 }'
        { New-BuildMatrix -Config $config } | Should -Throw '*max-parallel must be a positive integer*'
    }
}

Describe 'New-BuildMatrix - max-size validation' {
    It 'succeeds when the matrix is within max-size' {
        $config = ConvertToConfig @'
{ "matrix": { "os": ["ubuntu-latest", "windows-latest"], "node": ["18", "20"] },
  "max-size": 4 }
'@
        { New-BuildMatrix -Config $config } | Should -Not -Throw
    }

    It 'fails with a meaningful error when the matrix exceeds max-size' {
        $config = ConvertToConfig @'
{ "matrix": { "os": ["ubuntu-latest", "windows-latest"], "node": ["18", "20", "22"] },
  "max-size": 4 }
'@
        { New-BuildMatrix -Config $config } |
            Should -Throw '*6 combinations, which exceeds the configured max-size of 4*'
    }
}

Describe 'New-BuildMatrix - error handling' {
    It 'throws when the config is null' {
        { New-BuildMatrix -Config $null } | Should -Throw '*null*'
    }

    It 'throws when the matrix section is missing' {
        $config = ConvertToConfig '{ "max-parallel": 2 }'
        { New-BuildMatrix -Config $config } | Should -Throw '*missing the required "matrix" section*'
    }

    It 'throws when there are no dimensions and no include list' {
        $config = ConvertToConfig '{ "matrix": { } }'
        { New-BuildMatrix -Config $config } | Should -Throw '*at least one dimension or an "include" list*'
    }

    It 'throws when every combination is excluded' {
        $config = ConvertToConfig @'
{ "matrix": { "os": ["ubuntu-latest"], "exclude": [ { "os": "ubuntu-latest" } ] } }
'@
        { New-BuildMatrix -Config $config } | Should -Throw '*resolved matrix is empty*'
    }
}

Describe 'ConvertTo-MatrixJson - output shape' {
    It 'round-trips through fromJson-style parsing with include as an array' {
        $config = ConvertToConfig '{ "matrix": { "os": ["ubuntu-latest"], "node": ["18"] } }'
        $json = New-BuildMatrix -Config $config | ConvertTo-MatrixJson -Compress
        $parsed = $json | ConvertFrom-Json
        # include must be a JSON array even with a single element.
        @($parsed.matrix.include).Count | Should -Be 1
        $parsed.matrix.include[0].os | Should -Be 'ubuntu-latest'
        $parsed.size | Should -Be 1
    }
}
