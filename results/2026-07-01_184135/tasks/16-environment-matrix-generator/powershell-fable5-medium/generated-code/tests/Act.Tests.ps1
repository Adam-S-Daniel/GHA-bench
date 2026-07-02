# End-to-end pipeline tests: run the GitHub Actions workflow via act (Docker)
# and assert EXACT expected values in the output.
#
# Harness design:
#   - A temp git repo is created with the project files and all fixture data.
#   - `act push --rm` is executed ONCE (the workflow itself runs every test
#     case: both success fixtures, the size-limit error fixture, the full
#     Pester unit suite, and the 4-leg consume-matrix fan-out).
#   - The complete output is appended to act-result.txt (required artifact),
#     delimited per test case.
#   - Each It below asserts one case's exact known-good value from the
#     captured output.

BeforeAll {
    $script:repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:resultFile = Join-Path $repoRoot 'act-result.txt'
    $script:tempRepo   = Join-Path ([IO.Path]::GetTempPath()) "matrix-generator-act-$PID"

    # Start the artifact fresh for this suite run; each case is appended below.
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

    # --- Set up a temp git repo with project files + fixture data -----------
    if (Test-Path $tempRepo) { Remove-Item $tempRepo -Recurse -Force }
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    foreach ($item in @('src', 'fixtures', '.github', '.actrc')) {
        Copy-Item (Join-Path $repoRoot $item) (Join-Path $tempRepo $item) -Recurse
    }
    # Only the unit test file goes into the container (this act harness must
    # not recurse into itself).
    New-Item -ItemType Directory -Path (Join-Path $tempRepo 'tests') | Out-Null
    Copy-Item (Join-Path $repoRoot 'tests' 'MatrixGenerator.Tests.ps1') (Join-Path $tempRepo 'tests')

    git -C $tempRepo init -q -b main
    git -C $tempRepo -c user.email=ci@example.com -c user.name=ci add -A
    git -C $tempRepo -c user.email=ci@example.com -c user.name=ci commit -q -m 'act test case: all fixtures'

    # --- Run the workflow once through act ----------------------------------
    Push-Location $tempRepo
    try {
        # --pull=false: the runner image is provided locally; a forced pull
        # would fail against the registry.
        $script:actOutput = & act push --rm --pull=false -P ubuntu-latest=act-ubuntu-pwsh:latest 2>&1 |
            ForEach-Object { "$_" }
        $script:actExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    # --- Persist the required artifact, clearly delimited --------------------
    $header = @(
        '================================================================',
        'TEST CASES: basic | include-exclude | too-large (error path) |',
        '            unit-tests-in-container | consume-matrix fan-out',
        "act exit code: $script:actExit",
        '================================================================'
    )
    Add-Content -Path $resultFile -Value ($header + $script:actOutput)

    $script:actText = $script:actOutput -join "`n"
}

AfterAll {
    if (Test-Path $script:tempRepo) { Remove-Item $script:tempRepo -Recurse -Force }
}

Describe 'workflow execution through act' {
    It 'act exits with code 0' {
        $script:actExit | Should -Be 0
    }

    It 'writes the required act-result.txt artifact' {
        Test-Path $script:resultFile | Should -BeTrue
        (Get-Item $script:resultFile).Length | Should -BeGreaterThan 0
    }

    It 'case basic: outputs the exact 4-combination matrix JSON' {
        $expected = 'CASE[basic] {"fail-fast":true,"max-parallel":2,"matrix":{"include":[' +
            '{"os":"ubuntu-latest","node":"18"},' +
            '{"os":"ubuntu-latest","node":"20"},' +
            '{"os":"windows-latest","node":"18"},' +
            '{"os":"windows-latest","node":"20"}]}}'
        $script:actText.Contains($expected) | Should -BeTrue
    }

    It 'case include-exclude: outputs the exact matrix with exclude applied and include appended' {
        $expected = 'CASE[include-exclude] {"fail-fast":false,"max-parallel":3,"matrix":{"include":[' +
            '{"os":"ubuntu-latest","python":"3.11"},' +
            '{"os":"ubuntu-latest","python":"3.12"},' +
            '{"os":"macos-latest","python":"3.12"},' +
            '{"os":"ubuntu-latest","python":"3.13","experimental":true}]}}'
        $script:actText.Contains($expected) | Should -BeTrue
    }

    It 'case too-large: the size limit rejects the 8-combo matrix with the exact error' {
        $script:actText | Should -Match ([regex]::Escape('CASE[too-large] ERROR:') + '.*Matrix size 8 exceeds maximum allowed size 4')
    }

    It 'runs all 15 Pester unit tests inside the container' {
        $script:actText.Contains('UNIT-TESTS-PASSED count=15') | Should -BeTrue
    }

    It 'consume-matrix fans out into exactly the 4 generated legs' {
        foreach ($leg in @(
                'MATRIX-JOB os=ubuntu-latest node=18',
                'MATRIX-JOB os=ubuntu-latest node=20',
                'MATRIX-JOB os=windows-latest node=18',
                'MATRIX-JOB os=windows-latest node=20')) {
            $script:actText.Contains($leg) | Should -BeTrue -Because "leg '$leg' must run"
        }
    }

    It 'every job reports Job succeeded and none failed' {
        # unit-tests + generate-matrix + 4 consume-matrix legs = 6 jobs.
        $succeeded = @($script:actOutput | Where-Object { $_ -match 'Job succeeded' })
        $succeeded.Count | Should -Be 6
        @($script:actOutput | Where-Object { $_ -match 'Job failed' }).Count | Should -Be 0
    }
}
