#
# Pester tests for the Aggregate-TestResults.ps1 CLI entry point.
#
BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'Aggregate-TestResults.ps1'
    $MatrixFixturesPath = Join-Path $PSScriptRoot '..' 'fixtures' 'matrix-build'
    $AllPassingFixturesPath = Join-Path $PSScriptRoot '..' 'fixtures' 'all-passing'
}

Describe 'Aggregate-TestResults.ps1' {
    Context 'Happy path: aggregating a directory of matrix-build result files' {
        BeforeAll {
            $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "aggregate-test-$([guid]::NewGuid()).md"
            & $ScriptPath -Path $MatrixFixturesPath -OutputPath $outputFile
            $exitCode = $LASTEXITCODE
            $content = Get-Content -LiteralPath $outputFile -Raw
        }

        AfterAll {
            Remove-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
        }

        It 'Exits with code 0' {
            $exitCode | Should -Be 0
        }

        It 'Writes a markdown file with the expected totals' {
            $content | Should -Match '\| Total \| 18 \|'
            $content | Should -Match '\| Passed \| 12 \|'
            $content | Should -Match '\| Failed \| 2 \|'
            $content | Should -Match '\| Skipped \| 4 \|'
        }

        It 'Lists the flaky tests' {
            $content | Should -Match 'rate_limit_blocks_after_5_attempts'
            $content | Should -Match 'refund_processes'
        }
    }

    Context 'A directory with no flaky tests (all-passing fixtures)' {
        # Regression test: Find-FlakyTests returns zero objects when nothing is
        # flaky, which PowerShell unrolls to $null when captured in a variable.
        # The script must not crash when it forwards that to -FlakyTests.
        BeforeAll {
            $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "aggregate-nofaky-$([guid]::NewGuid()).md"
            & $ScriptPath -Path $AllPassingFixturesPath -OutputPath $outputFile
            $exitCode = $LASTEXITCODE
            $content = Get-Content -LiteralPath $outputFile -Raw
        }

        AfterAll {
            Remove-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
        }

        It 'Exits with code 0' {
            $exitCode | Should -Be 0
        }

        It 'Reports the friendly no-flaky-tests message' {
            $content | Should -Match 'No flaky tests detected'
        }

        It 'Reports all tests passed' {
            $content | Should -Match '\| Total \| 6 \|'
            $content | Should -Match '\| Passed \| 6 \|'
            $content | Should -Match '\| Failed \| 0 \|'
        }
    }

    Context 'Error handling' {
        It 'Throws a meaningful error and exits non-zero for a missing directory' {
            $missingDir = Join-Path ([System.IO.Path]::GetTempPath()) "does-not-exist-$([guid]::NewGuid())"
            & $ScriptPath -Path $missingDir 2>$null
            $LASTEXITCODE | Should -Not -Be 0
        }

        It 'Throws a meaningful error and exits non-zero when the directory has no result files' {
            $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) "empty-$([guid]::NewGuid())"
            New-Item -ItemType Directory -Path $emptyDir | Out-Null
            try {
                & $ScriptPath -Path $emptyDir 2>$null
                $LASTEXITCODE | Should -Not -Be 0
            } finally {
                Remove-Item -LiteralPath $emptyDir -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    Context '-FailOnTestFailure switch' {
        It 'Exits non-zero when there are failed tests and -FailOnTestFailure is set' {
            $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "aggregate-fail-$([guid]::NewGuid()).md"
            try {
                & $ScriptPath -Path $MatrixFixturesPath -OutputPath $outputFile -FailOnTestFailure 2>$null
                $LASTEXITCODE | Should -Not -Be 0
            } finally {
                Remove-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
            }
        }

        It 'Exits 0 when there are failed tests but -FailOnTestFailure is NOT set' {
            $outputFile = Join-Path ([System.IO.Path]::GetTempPath()) "aggregate-nofail-$([guid]::NewGuid()).md"
            try {
                & $ScriptPath -Path $MatrixFixturesPath -OutputPath $outputFile
                $LASTEXITCODE | Should -Be 0
            } finally {
                Remove-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
            }
        }
    }
}
