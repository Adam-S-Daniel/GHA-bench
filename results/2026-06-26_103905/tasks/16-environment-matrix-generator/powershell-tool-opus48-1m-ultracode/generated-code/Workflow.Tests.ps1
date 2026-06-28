<#
  Workflow.Tests.ps1
  ------------------
  Acceptance tests that drive EVERY case through the real GitHub Actions pipeline
  using `act` (nektos/act) in Docker -- not the script directly.

  To stay within a small number of `act` invocations, the workflow's `generate`
  job runs all fixtures in a single pass and prints clearly-delimited, machine
  checkable blocks. This BeforeAll runs `act push` exactly once, saves the full
  output to act-result.txt (a required artifact), and the It blocks below assert
  on EXACT expected values parsed from that one run -- including the downstream
  `build` matrix jobs that consume the generated matrix via fromJSON.
#>

# ---- run act once ----------------------------------------------------------
# NOTE: helper functions are defined inside this top-level BeforeAll so they are
# available to every It block during Pester v5's run phase.

BeforeAll {
    function Remove-AnsiCode {
        param([string]$Text)
        return ($Text -replace '\x1b\[[0-9;]*m', '')
    }

    function Get-FixtureBlock {
        # Text between ===FIXTURE-BEGIN:<name>=== and ===FIXTURE-END:<name>===
        param([string]$Name)
        $escaped = [regex]::Escape($Name)
        $pattern = "(?s)===FIXTURE-BEGIN:$escaped===(.*?)===FIXTURE-END:$escaped==="
        $m = [regex]::Match($script:ActOutput, $pattern)
        if (-not $m.Success) { return $null }
        return $m.Groups[1].Value
    }

    function Get-FixtureMatrix {
        # Parse the compact result JSON emitted on the MATRIX: line of a block.
        param([string]$Name)
        $block = Get-FixtureBlock -Name $Name
        if ($null -eq $block) { return $null }
        $m = [regex]::Match($block, 'MATRIX:(\{.*)')
        if (-not $m.Success) { return $null }
        return ($m.Groups[1].Value.Trim() | ConvertFrom-Json)
    }

    $script:Root      = $PSScriptRoot
    $script:ActResult = Join-Path $Root 'act-result.txt'

    # Assemble an isolated git repo containing only the project files act needs.
    $script:Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("matrix-act-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null

    foreach ($item in 'BuildMatrix.psm1', 'Invoke-MatrixGenerator.ps1', '.actrc') {
        Copy-Item -LiteralPath (Join-Path $Root $item) -Destination (Join-Path $Temp $item) -Force
    }
    Copy-Item -Path (Join-Path $Root 'fixtures') -Destination (Join-Path $Temp 'fixtures') -Recurse -Force
    Copy-Item -Path (Join-Path $Root '.github')  -Destination (Join-Path $Temp '.github')  -Recurse -Force

    # Commit so `act push` has a ref to run against; force branch `main` so it
    # matches the workflow's branch filter.
    git -C $Temp init -q | Out-Null
    git -C $Temp config user.email 'ci@example.com' | Out-Null
    git -C $Temp config user.name  'CI' | Out-Null
    git -C $Temp config commit.gpgsign false | Out-Null
    git -C $Temp add -A | Out-Null
    git -C $Temp commit -q -m 'matrix generator test' | Out-Null
    git -C $Temp branch -M main | Out-Null

    # Run the pipeline. Explicit -P guarantees the pwsh-enabled image; --pull=false
    # avoids trying to pull our local-only image.
    Push-Location $Temp
    try {
        $raw = & act push `
            -P ubuntu-latest=act-ubuntu-pwsh:latest `
            --pull=false `
            --rm 2>&1 | Out-String
        $script:ActExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $script:ActOutput = Remove-AnsiCode $raw

    # Persist the required artifact (delimited, with the exit code recorded).
    $header = @(
        '================================================================'
        "act push run for environment-matrix-generator workflow"
        "exit code: $script:ActExit"
        'Fixtures are delimited inline by ===FIXTURE-BEGIN/END:<name>=== markers.'
        '================================================================'
        ''
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $ActResult -Value ($header + $script:ActOutput) -Encoding utf8

    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Pipeline run via act' {
    It 'produces the required act-result.txt artifact' {
        Test-Path -LiteralPath $ActResult | Should -BeTrue
        (Get-Content -LiteralPath $ActResult -Raw).Length | Should -BeGreaterThan 0
    }

    It 'exits with code 0' {
        $ActExit | Should -Be 0
    }

    It 'reports every job as succeeded and none failed' {
        $ActOutput | Should -Not -Match 'Job failed'
        # generate (1) + build matrix jobs (3 for the primary config) = 4
        ([regex]::Matches($ActOutput, 'Job succeeded')).Count | Should -BeGreaterOrEqual 4
    }
}

Describe 'Fixture: a-basic (axes + exclude + max-parallel + fail-fast)' {
    It 'succeeds with size 3' {
        Get-FixtureBlock 'a-basic' | Should -Match 'STATUS:OK'
        Get-FixtureBlock 'a-basic' | Should -Match 'SIZE:3'
    }

    It 'produces exactly ubuntu/18, ubuntu/20, windows/20 (windows/18 excluded)' {
        $m = Get-FixtureMatrix 'a-basic'
        $inc = @($m.strategy.matrix.include)
        $inc.Count | Should -Be 3
        ($inc | Where-Object { $_.os -eq 'ubuntu-latest'  -and $_.node -eq '18' }).Count | Should -Be 1
        ($inc | Where-Object { $_.os -eq 'ubuntu-latest'  -and $_.node -eq '20' }).Count | Should -Be 1
        ($inc | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '20' }).Count | Should -Be 1
        @($inc | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq '18' }).Count | Should -Be 0
    }

    It 'carries fail-fast=false and max-parallel=2 through to the strategy' {
        $m = Get-FixtureMatrix 'a-basic'
        $m.strategy.'fail-fast'    | Should -BeFalse
        $m.strategy.'max-parallel' | Should -Be 2
    }
}

Describe 'Fixture: b-include (GitHub documented include algorithm)' {
    It 'succeeds with size 6' {
        Get-FixtureBlock 'b-include' | Should -Match 'STATUS:OK'
        Get-FixtureBlock 'b-include' | Should -Match 'SIZE:6'
    }

    It 'matches the documented fruit/animal expansion exactly' {
        $inc = @((Get-FixtureMatrix 'b-include').strategy.matrix.include)
        $inc.Count | Should -Be 6
        # apple+cat: color overridden to pink, shape added
        $inc[0].fruit | Should -Be 'apple'; $inc[0].animal | Should -Be 'cat'
        $inc[0].color | Should -Be 'pink';  $inc[0].shape  | Should -Be 'circle'
        # apple+dog keeps green, still gets shape
        $inc[1].color | Should -Be 'green'; $inc[1].shape  | Should -Be 'circle'
        # standalone banana entries appended at the end
        $inc[4].fruit | Should -Be 'banana'
        $inc[5].fruit | Should -Be 'banana'; $inc[5].animal | Should -Be 'cat'
    }
}

Describe 'Fixture: c-oversize (max-size validation)' {
    It 'is rejected with a meaningful error' {
        $block = Get-FixtureBlock 'c-oversize'
        $block | Should -Match 'STATUS:ERROR'
        $block | Should -Match 'max-size = 10, actual = 27'
    }
}

Describe 'Fixture: d-features (3 axes + feature flags + include-extend + partial exclude)' {
    It 'succeeds with size 3' {
        Get-FixtureBlock 'd-features' | Should -Match 'STATUS:OK'
        Get-FixtureBlock 'd-features' | Should -Match 'SIZE:3'
    }

    It 'extends the matching combo with experimental and drops 3.11/legacy' {
        $inc = @((Get-FixtureMatrix 'd-features').strategy.matrix.include)
        $inc.Count | Should -Be 3
        @($inc | Where-Object { $_.python -eq '3.11' -and $_.feature -eq 'legacy' }).Count | Should -Be 0
        $modern = $inc | Where-Object { $_.python -eq '3.12' -and $_.feature -eq 'modern' }
        @($modern).Count | Should -Be 1
        $modern.experimental | Should -BeTrue
    }
}

Describe 'Fixture: e-partial (partial exclude as wildcard)' {
    It 'removes every macos combination, leaving 6' {
        Get-FixtureBlock 'e-partial' | Should -Match 'SIZE:6'
        $inc = @((Get-FixtureMatrix 'e-partial').strategy.matrix.include)
        $inc.Count | Should -Be 6
        @($inc | Where-Object { $_.os -eq 'macos' }).Count | Should -Be 0
    }
}

Describe 'Downstream build job consumes the generated matrix' {
    # The build job expands fromJSON(needs.generate.outputs.matrix) for the primary
    # config and echoes each combination -- proving the matrix is valid and usable.
    It 'runs exactly the three expected combinations' {
        $ActOutput | Should -Match 'BUILD os=ubuntu-latest node=18'
        $ActOutput | Should -Match 'BUILD os=ubuntu-latest node=20'
        $ActOutput | Should -Match 'BUILD os=windows-latest node=20'
    }

    It 'does not run the excluded windows/18 combination' {
        $ActOutput | Should -Not -Match 'BUILD os=windows-latest node=18'
    }
}
