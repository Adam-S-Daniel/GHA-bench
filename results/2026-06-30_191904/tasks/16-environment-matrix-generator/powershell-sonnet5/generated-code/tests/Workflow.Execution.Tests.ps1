# Pipeline execution tests: actually run the GitHub Actions workflow via
# `act` in Docker (not the script directly) and assert on exact values in
# the captured output. All three fixture scenarios (basic cartesian product,
# full include/exclude/fail-fast/max-parallel, and max-size rejection) are
# exercised as separate steps within a single `act push` run, so the whole
# pipeline is validated with one Docker invocation.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ResultPath = Join-Path $RepoRoot 'act-result.txt'

    $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "matrix-act-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $TempRepo | Out-Null

    foreach ($item in @('EnvironmentMatrixGenerator.psm1', 'Generate-Matrix.ps1', '.actrc')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $item) -Destination (Join-Path $TempRepo $item)
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures') -Destination (Join-Path $TempRepo 'fixtures') -Recurse
    Copy-Item -LiteralPath (Join-Path $RepoRoot '.github') -Destination (Join-Path $TempRepo '.github') -Recurse

    Push-Location $TempRepo
    try {
        git init -q
        git config user.email 'matrix-test@example.com'
        git config user.name 'Matrix Test'
        git add -A
        git commit -q -m 'test commit'

        $script:ActOutput = (& act push --rm 2>&1 | Out-String)
        $script:ActExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $delimiter = '=' * 80
    $header = "$delimiter`nACT EXECUTION - Environment Matrix Generator - $(Get-Date -Format o)`nExit code: $ActExitCode`n$delimiter`n"
    Add-Content -LiteralPath $ResultPath -Value $header
    Add-Content -LiteralPath $ResultPath -Value $ActOutput

    Remove-Item -LiteralPath $TempRepo -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Environment matrix generator workflow execution (via act)' {
    It 'exits with code 0' {
        $ActExitCode | Should -Be 0
    }

    It 'produces the act-result.txt artifact' {
        Test-Path -LiteralPath $ResultPath | Should -BeTrue
    }

    It 'reports success for both jobs' {
        $matches = [regex]::Matches($ActOutput, 'Job succeeded')
        $matches.Count | Should -BeGreaterOrEqual 2
    }

    It 'generates the exact basic-scenario matrix JSON (plain cartesian product, fail-fast defaulted true)' {
        $ActOutput -match 'MATRIX_JSON_BASIC:(\{.*\})' | Should -BeTrue
        $json = $Matches[1]
        $expected = '{"fail-fast":true,"matrix":{"include":[{"os":"ubuntu-latest","node":16},{"os":"ubuntu-latest","node":18},{"os":"windows-latest","node":16},{"os":"windows-latest","node":18}]}}'
        $json | Should -Be $expected

        $parsed = $json | ConvertFrom-Json
        $parsed.matrix.include.Count | Should -Be 4
        $parsed.'fail-fast' | Should -Be $true
    }

    It 'generates the exact full-scenario matrix JSON (exclude + include + fail-fast:false + max-parallel:3)' {
        $ActOutput -match 'MATRIX_JSON_FULL:(\{.*\})' | Should -BeTrue
        $json = $Matches[1]
        $expected = '{"fail-fast":false,"max-parallel":3,"matrix":{"include":[{"os":"ubuntu-latest","node":16},{"os":"ubuntu-latest","node":18,"experimental":true},{"os":"windows-latest","node":18},{"os":"macos-latest","node":20}]}}'
        $json | Should -Be $expected

        $parsed = $json | ConvertFrom-Json
        $parsed.matrix.include.Count | Should -Be 4
        $parsed.'max-parallel' | Should -Be 3
        $parsed.'fail-fast' | Should -Be $false
        ($parsed.matrix.include | Where-Object { $_.os -eq 'windows-latest' -and $_.node -eq 16 }) | Should -BeNullOrEmpty
        (($parsed.matrix.include | Where-Object { $_.os -eq 'ubuntu-latest' -and $_.node -eq 18 }).experimental) | Should -Be $true
    }

    It 'rejects the oversized matrix with exit code 1 and the expected error message' {
        $ActOutput -match 'MAX_SIZE_EXIT_CODE:(\d+)' | Should -BeTrue
        $Matches[1] | Should -Be '1'
        $ActOutput | Should -Match 'exceeds the configured maximum of 4'
        $ActOutput | Should -Match 'MAX_SIZE_CHECK:PASSED'
    }
}
