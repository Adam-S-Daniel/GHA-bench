<#
    Act-driven pipeline test harness.

    This is the ONLY place the environment matrix generator's actual logic
    is verified end-to-end: it copies the project into an isolated temp git
    repository, runs the real GitHub Actions workflow with `act push --rm`
    in Docker, and asserts on the captured output. The generator script is
    never invoked directly from this file -- every assertion is against what
    the containerized pipeline itself printed or returned.

    A single "===TESTCASE_<NAME>_START===" / "===TESTCASE_<NAME>_END==="
    pair per fixture lets one `act push` run exercise every fixture-driven
    test case as a distinct, independently-assertable section of one
    workflow run, instead of needing one `act push` invocation per case.
#>

BeforeDiscovery {
    $script:RepoRoot = $PSScriptRoot
    $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'
}

BeforeAll {
    function Get-DelimitedJson {
        param(
            [Parameter(Mandatory)] [string[]]$Lines,
            [Parameter(Mandatory)] [string]$StartMarker,
            [Parameter(Mandatory)] [string]$EndMarker
        )

        $startMatch = $Lines | Select-String -SimpleMatch $StartMarker | Select-Object -First 1
        $endMatch = $Lines | Select-String -SimpleMatch $EndMarker | Select-Object -First 1
        if (-not $startMatch -or -not $endMatch) {
            throw "Could not locate delimiters '$StartMarker' / '$EndMarker' in act output."
        }

        # Select-String reports 1-based line numbers; the array indices
        # strictly between the two marker lines are (startLineNumber) ..
        # (endLineNumber - 2).
        $jsonLines = $Lines[$startMatch.LineNumber..($endMatch.LineNumber - 2)]

        $jsonText = ($jsonLines | ForEach-Object {
                $braceIndex = $_.IndexOf('{')
                if ($braceIndex -ge 0) { $_.Substring($braceIndex) } else { '' }
            }) -join ''

        return $jsonText
    }

    $script:TempRepoPath = Join-Path ([System.IO.Path]::GetTempPath()) "environment-matrix-generator-act-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $TempRepoPath -Force | Out-Null

    Copy-Item -Path (Join-Path $RepoRoot 'EnvironmentMatrixGenerator.ps1') -Destination $TempRepoPath
    Copy-Item -Path (Join-Path $RepoRoot 'MatrixFunctions.ps1') -Destination $TempRepoPath
    Copy-Item -Path (Join-Path $RepoRoot 'EnvironmentMatrixGenerator.Tests.ps1') -Destination $TempRepoPath
    Copy-Item -Path (Join-Path $RepoRoot 'fixtures') -Destination $TempRepoPath -Recurse
    Copy-Item -Path (Join-Path $RepoRoot '.github') -Destination $TempRepoPath -Recurse
    Copy-Item -Path (Join-Path $RepoRoot '.actrc') -Destination $TempRepoPath

    Push-Location $TempRepoPath
    try {
        git init --quiet --initial-branch=main .
        git config user.email 'act-harness@example.com'
        git config user.name 'Act Harness'
        git add -A
        git commit --quiet --message 'test: environment matrix generator pipeline run'

        $actArgs = @('push', '--rm', '--pull=false')
        $script:ActOutputLines = @(& act @actArgs 2>&1 | ForEach-Object { $_.ToString() })
        $script:ActExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $header = "===== act push --rm  (run at $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'), exit code $ActExitCode) ====="
    $footer = '===== end act push ====='
    @($header; $ActOutputLines; $footer; '') | Add-Content -Path $ActResultPath -Encoding utf8

    $script:BasicMatrixJson = $null
    $script:ExcludesMatrixJson = $null
    $script:IncludesMatrixJson = $null
    try { $script:BasicMatrixJson = Get-DelimitedJson -Lines $ActOutputLines -StartMarker '===TESTCASE_BASIC_START===' -EndMarker '===TESTCASE_BASIC_END===' } catch {}
    try { $script:ExcludesMatrixJson = Get-DelimitedJson -Lines $ActOutputLines -StartMarker '===TESTCASE_EXCLUDES_START===' -EndMarker '===TESTCASE_EXCLUDES_END===' } catch {}
    try { $script:IncludesMatrixJson = Get-DelimitedJson -Lines $ActOutputLines -StartMarker '===TESTCASE_INCLUDES_START===' -EndMarker '===TESTCASE_INCLUDES_END===' } catch {}
}

AfterAll {
    if ($TempRepoPath -and (Test-Path $TempRepoPath)) {
        Remove-Item -Path $TempRepoPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'act pipeline execution' {
    It 'produces the act-result.txt artifact' {
        Test-Path $ActResultPath | Should -Be $true
        (Get-Item $ActResultPath).Length | Should -BeGreaterThan 0
    }

    It 'exits with code 0' {
        $ActExitCode | Should -Be 0 -Because ($ActOutputLines -join "`n")
    }

    It 'reports "Job succeeded" once each for test and generate, and once per use-matrix fan-out instance' {
        # use-matrix is a matrix job: it runs once per combination in the basic
        # test case (4), so the total is 1 (test) + 1 (generate) + 4 (use-matrix).
        $successCount = ($ActOutputLines | Select-String -SimpleMatch 'Job succeeded').Count
        $successCount | Should -Be 6 -Because ($ActOutputLines -join "`n")
    }
}

Describe 'act pipeline test case: basic-config.json' {
    It 'produced parseable JSON for the basic test case' {
        $BasicMatrixJson | Should -Not -BeNullOrEmpty
    }

    It 'contains exactly the 4 expected combinations in cartesian order' {
        $parsed = $BasicMatrixJson | ConvertFrom-Json
        $include = $parsed.strategy.matrix.include

        $include.Count | Should -Be 4
        $include[0].os | Should -Be 'ubuntu-latest'
        $include[0].version | Should -Be '18'
        $include[1].os | Should -Be 'ubuntu-latest'
        $include[1].version | Should -Be '20'
        $include[2].os | Should -Be 'windows-latest'
        $include[2].version | Should -Be '18'
        $include[3].os | Should -Be 'windows-latest'
        $include[3].version | Should -Be '20'
    }

    It 'carries through the configured fail-fast and max-parallel values exactly' {
        $parsed = $BasicMatrixJson | ConvertFrom-Json
        $parsed.strategy.'fail-fast' | Should -Be $true
        $parsed.strategy.'max-parallel' | Should -Be 2
    }
}

Describe 'act pipeline test case: excludes-config.json' {
    It 'produced parseable JSON for the excludes test case' {
        $ExcludesMatrixJson | Should -Not -BeNullOrEmpty
    }

    It 'excludes exactly the macos-latest/18 combination, leaving 5 of 6' {
        $parsed = $ExcludesMatrixJson | ConvertFrom-Json
        $include = $parsed.strategy.matrix.include

        $include.Count | Should -Be 5
        ($include | Where-Object { $_.os -eq 'macos-latest' -and $_.version -eq '18' }).Count | Should -Be 0
        ($include | Where-Object { $_.os -eq 'macos-latest' -and $_.version -eq '20' }).Count | Should -Be 1
    }

    It 'reflects the configured fail-fast: false' {
        $parsed = $ExcludesMatrixJson | ConvertFrom-Json
        $parsed.strategy.'fail-fast' | Should -Be $false
    }
}

Describe 'act pipeline test case: includes-config.json' {
    It 'produced parseable JSON for the includes test case' {
        $IncludesMatrixJson | Should -Not -BeNullOrEmpty
    }

    It 'merges the matching include into ubuntu-latest/18 and appends the new macos-latest/20 entry' {
        $parsed = $IncludesMatrixJson | ConvertFrom-Json
        $include = $parsed.strategy.matrix.include

        $include.Count | Should -Be 3

        $ubuntu = $include | Where-Object { $_.os -eq 'ubuntu-latest' }
        $ubuntu.version | Should -Be '18'
        $ubuntu.flags | Should -Be 'experimental'

        $macos = $include | Where-Object { $_.os -eq 'macos-latest' }
        $macos.version | Should -Be '20'
        $macos.flags | Should -Be 'beta'
    }
}
