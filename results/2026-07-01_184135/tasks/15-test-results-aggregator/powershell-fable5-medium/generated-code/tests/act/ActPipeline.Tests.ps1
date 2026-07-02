<#
.SYNOPSIS
    End-to-end pipeline tests: run the GitHub Actions workflow via act.

.DESCRIPTION
    For each test case this harness:
      1. Builds a temp git repo containing the project files plus that
         case's fixture set (swapped into fixtures/).
      2. Runs `act push --rm` against it.
      3. Appends the full act output to act-result.txt in the repo root,
         clearly delimited per case.
      4. Asserts act exited 0, every job reported "Job succeeded", and
         the workflow output contains the EXACT expected aggregate values
         for that case's fixture data.

    NOTE: each Invoke-Pester of this file performs one `act push` per
    case (2 total). act runs take 30-90s each.
#>

BeforeDiscovery {
    # One entry per pipeline test case. ExpectedText entries are matched
    # verbatim (escaped) against the act output.
    $script:Cases = @(
        @{
            Name        = 'matrix-with-flaky'
            FixtureDir  = 'fixtures'                     # 3 runs, 1 flaky, failures
            ExpectedText = @(
                'Aggregating 3 result file(s)'
                '| Total tests | 12 |'
                '| Passed | 5 |'
                '| Failed | 4 |'
                '| Skipped | 3 |'
                '| Duration | 4.55s |'
                'Flaky Tests (1)'
                '| SuiteA | flaky network call | 2 | 1 |'
                'Failed Tests (2)'
                '| SuiteA | divides by zero | 3 | run1-ubuntu.xml, run2-windows.xml, run3-macos.json |'
                '**Overall status:** ❌ FAILING'
            )
        }
        @{
            Name        = 'all-passing'
            FixtureDir  = 'tests/fixtures-allpass'       # 2 clean runs, no flaky
            ExpectedText = @(
                'Aggregating 2 result file(s)'
                '| Total tests | 4 |'
                '| Passed | 4 |'
                '| Failed | 0 |'
                '| Skipped | 0 |'
                '| Duration | 1.50s |'
                'No flaky tests detected'
                '**Overall status:** ✅ PASSING'
            )
        }
    )
}

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ResultFile = Join-Path $RepoRoot 'act-result.txt'

    # Start a fresh act-result.txt for this harness run.
    Set-Content -LiteralPath $ResultFile -Value "act pipeline test results - $(Get-Date -Format o)`n"

    # Display names of the workflow's jobs; act prefixes log lines with them.
    $script:JobNames = @('Pester unit tests', 'Aggregate results and publish summary')

    function script:Invoke-ActCase {
        param(
            [Parameter(Mandatory)][string]$CaseName,
            [Parameter(Mandatory)][string]$FixtureDir
        )

        # 1. Assemble a temp git repo: project files + this case's fixtures.
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) "act-$CaseName-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            Copy-Item (Join-Path $RepoRoot 'TestResultsAggregator.psm1') $temp
            Copy-Item (Join-Path $RepoRoot 'Invoke-TestResultsAggregator.ps1') $temp
            Copy-Item (Join-Path $RepoRoot '.actrc') $temp
            Copy-Item (Join-Path $RepoRoot '.github') $temp -Recurse
            # Unit tests + their private fixtures run inside the container too.
            New-Item -ItemType Directory -Path (Join-Path $temp 'tests') | Out-Null
            Copy-Item (Join-Path $RepoRoot 'tests' 'unit') (Join-Path $temp 'tests') -Recurse
            Copy-Item (Join-Path $RepoRoot 'tests' 'fixtures') (Join-Path $temp 'tests') -Recurse
            # The case's fixture set becomes the fixtures/ dir the workflow aggregates.
            Copy-Item (Join-Path $RepoRoot $FixtureDir) (Join-Path $temp 'fixtures') -Recurse

            Push-Location $temp
            try {
                git init -q 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git -c user.email='ci@example.com' -c user.name='ci' commit -qm "case $CaseName" 2>&1 | Out-Null

                # 2. Run the workflow via act (offline: image is pre-built locally).
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                # Strip ANSI colour codes so exact-value assertions are not
                # broken by escape sequences embedded in step output.
                $output = $output -replace "`e\[[0-9;]*m", ''
            }
            finally {
                Pop-Location
            }

            # 3. Append delimited output to the required artifact.
            Add-Content -LiteralPath $ResultFile -Value @(
                "===================== BEGIN CASE: $CaseName (exit=$exitCode) ====================="
                $output
                "===================== END CASE: $CaseName ====================="
                ''
            )

            return @{ ExitCode = $exitCode; Output = $output }
        }
        finally {
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'GitHub Actions pipeline via act - case <Name>' -ForEach $Cases {

    BeforeAll {
        $script:Run = Invoke-ActCase -CaseName $Name -FixtureDir $FixtureDir
    }

    It 'act exits with code 0' {
        $Run.ExitCode | Should -Be 0
    }

    It 'every job reports "Job succeeded" and none report failure' {
        foreach ($job in $JobNames) {
            # e.g. [Test Results Aggregator/Pester unit tests] 🏁  Job succeeded
            $Run.Output | Should -Match ([regex]::Escape($job) + '\].*Job succeeded')
        }
        $Run.Output | Should -Not -Match 'Job failed'
    }

    It 'unit tests ran green inside the pipeline' {
        $Run.Output | Should -Match 'Tests Passed: 27, Failed: 0'
    }

    It 'workflow output contains the exact expected value: <_>' -ForEach $ExpectedText {
        $Run.Output | Should -Match ([regex]::Escape($_))
    }
}

Describe 'act artifact' {

    It 'act-result.txt exists and contains both cases' {
        $ResultFile | Should -Exist
        $content = Get-Content -LiteralPath $ResultFile -Raw
        $content | Should -Match 'BEGIN CASE: matrix-with-flaky \(exit=0\)'
        $content | Should -Match 'BEGIN CASE: all-passing \(exit=0\)'
    }
}
