#
# Verifies the mandatory "ran for real through act" artifact: act-result.txt.
#
# act-result.txt is produced by Invoke-ActTestHarness.ps1 (a separate, manually
# run driver script -- NOT invoked from here). Each `act push` run takes
# 30-90s and spins up Docker containers, so this Pester file only READS the
# already-captured output and asserts against it. That keeps re-running the
# Pester suite fast/free and avoids exceeding the "at most 3 act push runs"
# budget every time the test suite is re-run.
#
BeforeAll {
    $RepoRoot = Join-Path $PSScriptRoot '..'
    $ActResultPath = Join-Path $RepoRoot 'act-result.txt'

    if (Test-Path -LiteralPath $ActResultPath) {
        $script:ActResultContent = Get-Content -LiteralPath $ActResultPath -Raw

        # Split into per-case blocks on the delimiter line Invoke-ActTestHarness.ps1 writes.
        $script:CaseBlocks = @{}
        $matches = [regex]::Matches(
            $script:ActResultContent,
            '(?ms)^={10,}\r?\nTEST CASE: (?<name>.+?)\r?\nSOURCE FIXTURES: .+?\r?\nEXIT CODE: (?<exit>-?\d+)\r?\n={10,}\r?\n(?<body>.*?)(?=^={10,}\r?\nTEST CASE:|\z)'
        )
        foreach ($m in $matches) {
            $script:CaseBlocks[$m.Groups['name'].Value] = [PSCustomObject]@{
                ExitCode = [int]$m.Groups['exit'].Value
                Body     = $m.Groups['body'].Value
            }
        }
    }
}

Describe 'act-result.txt artifact' {
    It 'Exists in the current working directory' {
        Test-Path -LiteralPath $ActResultPath | Should -BeTrue
    }

    It 'Is not empty' {
        (Get-Item -LiteralPath $ActResultPath).Length | Should -BeGreaterThan 0
    }

    It 'Contains both expected test cases' {
        $CaseBlocks.Keys | Should -Contain 'mixed-matrix-with-failures-and-flaky'
        $CaseBlocks.Keys | Should -Contain 'all-passing-clean-matrix'
    }
}

Describe 'act push exit codes' {
    It 'Exited 0 for the mixed-matrix-with-failures-and-flaky case' {
        $CaseBlocks['mixed-matrix-with-failures-and-flaky'].ExitCode | Should -Be 0
    }

    It 'Exited 0 for the all-passing-clean-matrix case' {
        $CaseBlocks['all-passing-clean-matrix'].ExitCode | Should -Be 0
    }
}

Describe 'Every job reports success' {
    It 'Both jobs succeed in the mixed-matrix-with-failures-and-flaky case' {
        $body = $CaseBlocks['mixed-matrix-with-failures-and-flaky'].Body
        (Select-String -InputObject $body -Pattern 'Job succeeded' -AllMatches).Matches.Count | Should -Be 2
        $body | Should -Not -Match 'Job failed'
    }

    It 'Both jobs succeed in the all-passing-clean-matrix case' {
        $body = $CaseBlocks['all-passing-clean-matrix'].Body
        (Select-String -InputObject $body -Pattern 'Job succeeded' -AllMatches).Matches.Count | Should -Be 2
        $body | Should -Not -Match 'Job failed'
    }
}

Describe 'act output matches exact known-good aggregate values' {
    Context 'mixed-matrix-with-failures-and-flaky' {
        BeforeAll {
            $body = $CaseBlocks['mixed-matrix-with-failures-and-flaky'].Body
        }

        It 'Reports exactly Total 18, Passed 12, Failed 2, Skipped 4, Duration 3.73' {
            $body | Should -Match '\|\s*Total\s*\|\s*18\s*\|'
            $body | Should -Match '\|\s*Passed\s*\|\s*12\s*\|'
            $body | Should -Match '\|\s*Failed\s*\|\s*2\s*\|'
            $body | Should -Match '\|\s*Skipped\s*\|\s*4\s*\|'
            $body | Should -Match '\|\s*Duration \(s\)\s*\|\s*3\.73\s*\|'
        }

        It 'Flags exactly the two expected flaky tests by name and by which files they passed/failed in' {
            $body | Should -Match 'rate_limit_blocks_after_5_attempts.*junit-windows-node18\.xml.*junit-ubuntu-node18\.xml'
            $body | Should -Match 'refund_processes.*json-macos-node20\.json.*json-ubuntu-node20\.json'
        }

        It 'Ran all 48 local Pester unit tests with zero failures' {
            $body | Should -Match 'Tests Passed: 48,.*Failed: 0,'
        }
    }

    Context 'all-passing-clean-matrix' {
        BeforeAll {
            $body = $CaseBlocks['all-passing-clean-matrix'].Body
        }

        It 'Reports exactly Total 6, Passed 6, Failed 0, Skipped 0, Duration 0.65' {
            $body | Should -Match '\|\s*Total\s*\|\s*6\s*\|'
            $body | Should -Match '\|\s*Passed\s*\|\s*6\s*\|'
            $body | Should -Match '\|\s*Failed\s*\|\s*0\s*\|'
            $body | Should -Match '\|\s*Skipped\s*\|\s*0\s*\|'
            $body | Should -Match '\|\s*Duration \(s\)\s*\|\s*0\.65\s*\|'
        }

        It 'Reports no flaky tests' {
            $body | Should -Match 'No flaky tests detected'
        }

        It 'Ran all 48 local Pester unit tests with zero failures' {
            $body | Should -Match 'Tests Passed: 48,.*Failed: 0,'
        }
    }
}
