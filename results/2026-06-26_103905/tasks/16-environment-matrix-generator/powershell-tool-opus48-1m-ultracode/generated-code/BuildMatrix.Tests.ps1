<#
  BuildMatrix.Tests.ps1 — fast unit tests driving the BuildMatrix module via red/green TDD.

  These tests exercise the pure matrix-generation logic directly so each red/green
  cycle is instant. The act-based pipeline tests (Workflow.Tests.ps1) are the
  acceptance layer that runs every case end-to-end through GitHub Actions.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/BuildMatrix.psm1" -Force
}

Describe 'Get-CartesianProduct' {
    It 'produces the full cartesian product of two axes' {
        $axes = [ordered]@{ os = @('ubuntu', 'windows'); node = @('18', '20') }
        $result = @(Get-CartesianProduct -Axes $axes)
        $result.Count | Should -Be 4
    }

    It 'varies the first declared axis slowest (outermost loop)' {
        $axes = [ordered]@{ os = @('ubuntu', 'windows'); node = @('18', '20') }
        $result = @(Get-CartesianProduct -Axes $axes)
        $result[0].os | Should -Be 'ubuntu'; $result[0].node | Should -Be '18'
        $result[1].os | Should -Be 'ubuntu'; $result[1].node | Should -Be '20'
        $result[2].os | Should -Be 'windows'; $result[2].node | Should -Be '18'
        $result[3].os | Should -Be 'windows'; $result[3].node | Should -Be '20'
    }

    It 'throws a meaningful error when an axis is empty' {
        $axes = [ordered]@{ os = @('ubuntu'); node = @() }
        { Get-CartesianProduct -Axes $axes } | Should -Throw '*axis*node*no values*'
    }
}

Describe 'Get-BuildMatrix exclude rules' {
    It 'removes a fully-specified combination' {
        $cfg = '{ "matrix": { "os": ["ubuntu-latest","windows-latest"], "node": ["18","20"] },
                  "exclude": [ { "os": "windows-latest", "node": "18" } ] }' | ConvertFrom-Json
        $r = Get-BuildMatrix -Config $cfg
        $combos = @($r.strategy.matrix.include)
        $combos.Count | Should -Be 3
        ($combos | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }).Count | Should -Be 0
    }

    It 'treats a partial exclude as a wildcard removing every match' {
        $cfg = '{ "matrix": { "os": ["ubuntu","windows","macos"], "node": ["16","18","20"] },
                  "exclude": [ { "os": "macos" } ] }' | ConvertFrom-Json
        $r = Get-BuildMatrix -Config $cfg
        @($r.strategy.matrix.include).Count | Should -Be 6
        (@($r.strategy.matrix.include) | Where-Object { $_.os -eq 'macos' }).Count | Should -Be 0
    }
}

Describe 'Get-BuildMatrix include rules (GitHub documented algorithm)' {
    # This is the exact fruit/animal example from the GitHub Actions documentation.
    BeforeAll {
        $cfg = '{
          "matrix": { "fruit": ["apple","pear"], "animal": ["cat","dog"] },
          "include": [
            { "color": "green" },
            { "color": "pink", "animal": "cat" },
            { "fruit": "apple", "shape": "circle" },
            { "fruit": "banana" },
            { "fruit": "banana", "animal": "cat" }
          ]
        }' | ConvertFrom-Json
        $script:combos = @((Get-BuildMatrix -Config $cfg).strategy.matrix.include)
    }

    It 'produces exactly six combinations in documented order' {
        $combos.Count | Should -Be 6
    }

    It 'overrides added (not original) values and adds keys to existing combos' {
        # apple+cat: color overwritten to pink by 2nd include, shape added by 3rd
        $combos[0].fruit | Should -Be 'apple'; $combos[0].animal | Should -Be 'cat'
        $combos[0].color | Should -Be 'pink';  $combos[0].shape | Should -Be 'circle'
        # apple+dog keeps green, still gets shape
        $combos[1].fruit | Should -Be 'apple'; $combos[1].animal | Should -Be 'dog'
        $combos[1].color | Should -Be 'green'; $combos[1].shape | Should -Be 'circle'
        # pear+cat -> pink, no shape
        $combos[2].color | Should -Be 'pink'
        $combos[2].PSObject.Properties.Name | Should -Not -Contain 'shape'
        # pear+dog -> green
        $combos[3].color | Should -Be 'green'
    }

    It 'appends standalone combinations when an include matches no original combo' {
        $combos[4].fruit | Should -Be 'banana'
        $combos[4].PSObject.Properties.Name | Should -Not -Contain 'animal'
        $combos[5].fruit | Should -Be 'banana'; $combos[5].animal | Should -Be 'cat'
    }
}

Describe 'Get-BuildMatrix include extending an existing combination' {
    It 'adds extra keys to the single matching combo without creating a new one' {
        $cfg = '{
          "matrix": { "os": ["ubuntu-latest"], "python": ["3.11","3.12"], "feature": ["legacy","modern"] },
          "exclude": [ { "python": "3.11", "feature": "legacy" } ],
          "include": [ { "os": "ubuntu-latest", "python": "3.12", "feature": "modern", "experimental": true } ]
        }' | ConvertFrom-Json
        $combos = @((Get-BuildMatrix -Config $cfg).strategy.matrix.include)
        $combos.Count | Should -Be 3
        $modern = $combos | Where-Object { $_.python -eq '3.12' -and $_.feature -eq 'modern' }
        @($modern).Count | Should -Be 1
        $modern.experimental | Should -BeTrue
    }
}

Describe 'Get-BuildMatrix strategy metadata' {
    It 'defaults fail-fast to true and omits max-parallel when unset' {
        $cfg = '{ "matrix": { "os": ["ubuntu-latest"] } }' | ConvertFrom-Json
        $r = Get-BuildMatrix -Config $cfg
        $r.strategy.'fail-fast' | Should -BeTrue
        $r.strategy.PSObject.Properties.Name | Should -Not -Contain 'max-parallel'
        $r.size | Should -Be 1
        $r.valid | Should -BeTrue
    }

    It 'passes through fail-fast=false and max-parallel' {
        $cfg = '{ "matrix": { "os": ["a","b"] }, "fail-fast": false, "max-parallel": 2 }' | ConvertFrom-Json
        $r = Get-BuildMatrix -Config $cfg
        $r.strategy.'fail-fast' | Should -BeFalse
        $r.strategy.'max-parallel' | Should -Be 2
    }
}

Describe 'Get-BuildMatrix validation' {
    It 'throws when the matrix exceeds the maximum size' {
        $cfg = '{ "matrix": { "a": ["1","2","3"], "b": ["1","2","3"], "c": ["1","2","3"] }, "max-size": 10 }' | ConvertFrom-Json
        { Get-BuildMatrix -Config $cfg } | Should -Throw '*exceeds*maximum*10*27*'
    }

    It 'honours an explicit -MaxSize override' {
        $cfg = '{ "matrix": { "a": ["1","2"], "b": ["1","2"] } }' | ConvertFrom-Json
        { Get-BuildMatrix -Config $cfg -MaxSize 3 } | Should -Throw '*exceeds*'
    }

    It 'throws when there is nothing to build (no axes and no include)' {
        $cfg = '{ }' | ConvertFrom-Json
        { Get-BuildMatrix -Config $cfg } | Should -Throw '*at least one*'
    }

    It 'throws when the expanded matrix is empty after excludes' {
        $cfg = '{ "matrix": { "os": ["ubuntu"] }, "exclude": [ { "os": "ubuntu" } ] }' | ConvertFrom-Json
        { Get-BuildMatrix -Config $cfg } | Should -Throw '*empty*'
    }

    It 'rejects a non-positive max-parallel' {
        $cfg = '{ "matrix": { "os": ["a"] }, "max-parallel": 0 }' | ConvertFrom-Json
        { Get-BuildMatrix -Config $cfg } | Should -Throw '*max-parallel*'
    }
}

Describe 'Import-MatrixConfig' {
    It 'throws a clear error when the file does not exist' {
        { Import-MatrixConfig -Path "$PSScriptRoot/does-not-exist.json" } | Should -Throw '*not found*'
    }

    It 'throws a clear error on invalid JSON' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bad-" + [System.Guid]::NewGuid().ToString() + ".json")
        Set-Content -Path $tmp -Value '{ not valid json' -Encoding utf8
        try {
            { Import-MatrixConfig -Path $tmp } | Should -Throw '*JSON*'
        } finally {
            Remove-Item -Path $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'loads a valid config file' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ok-" + [System.Guid]::NewGuid().ToString() + ".json")
        Set-Content -Path $tmp -Value '{ "matrix": { "os": ["ubuntu-latest"] } }' -Encoding utf8
        try {
            $cfg = Import-MatrixConfig -Path $tmp
            $cfg.matrix.os | Should -Be 'ubuntu-latest'
        } finally {
            Remove-Item -Path $tmp -ErrorAction SilentlyContinue
        }
    }
}
