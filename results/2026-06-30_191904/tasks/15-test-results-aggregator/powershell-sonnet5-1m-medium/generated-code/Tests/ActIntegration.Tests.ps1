# End-to-end integration harness: actually runs the GitHub Actions workflow
# through `act` (in Docker) for each test case, asserting on exact expected
# aggregate values parsed from the real act output. All output is appended to
# act-result.txt in the repo root, which is a required artifact.
#
# Run with: Invoke-Pester ./Tests/ActIntegration.Tests.ps1

BeforeAll {
    $script:RepoRoot = Resolve-Path "$PSScriptRoot/.."
    $script:ActResultPath = Join-Path $RepoRoot 'act-result.txt'

    # Files/dirs to seed into each temp repo (everything act needs to run the workflow).
    $script:ProjectItems = @(
        'TestResultsAggregator.ps1',
        'Tests',
        'fixtures',
        '.github',
        '.actrc'
    )

    function New-TempRepo {
        param([string]$CaseName)

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "act-case-$CaseName-$PID"
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        foreach ($item in $ProjectItems) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot $item) -Destination (Join-Path $tempDir $item) -Recurse
        }

        return $tempDir
    }

    function Invoke-ActCase {
        param(
            [string]$CaseName,
            [string]$TempRepo
        )

        Push-Location $TempRepo
        try {
            git init -q
            git config user.email 'act-harness@example.com'
            git config user.name 'act-harness'
            git add -A
            git commit -q -m "test case: $CaseName"

            # --pull=false: the benchmark environment's act image is already
            # present locally: a forced pull attempts registry auth and fails.
            $output = & act push --rm --pull=false 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            $delimiter = "=" * 80
            $report = @(
                $delimiter
                "TEST CASE: $CaseName"
                $delimiter
                $output
                "EXIT CODE: $exitCode"
                ''
            ) -join [Environment]::NewLine

            Add-Content -LiteralPath $ActResultPath -Value $report

            return [PSCustomObject]@{
                Output   = $output
                ExitCode = $exitCode
            }
        } finally {
            Pop-Location
        }
    }
}

Describe 'act workflow execution: flaky matrix fixtures (default fixtures/matrix)' {
    BeforeAll {
        $script:TempRepo = New-TempRepo -CaseName 'flaky-matrix'
        $script:Result = Invoke-ActCase -CaseName 'flaky-matrix' -TempRepo $TempRepo
    }

    AfterAll {
        Remove-Item -LiteralPath $TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits with code 0' {
        $Result.ExitCode | Should -Be 0
    }

    It 'shows both jobs succeeding' {
        ($Result.Output | Select-String -Pattern 'Job succeeded' -AllMatches).Matches.Count | Should -Be 2
    }

    It 'reports the exact expected aggregate totals' {
        $Result.Output | Should -Match '\| Total \| 9 \|'
        $Result.Output | Should -Match '\| Passed \| 4 \|'
        $Result.Output | Should -Match '\| Failed \| 4 \|'
        $Result.Output | Should -Match '\| Skipped \| 1 \|'
        $Result.Output | Should -Match '\| Duration \(s\) \| 4\.7 \|'
    }

    It 'flags test_login as flaky and reports overall FAILURE' {
        $Result.Output | Should -Match '## Flaky Tests'
        $Result.Output | Should -Match 'test_login'
        $Result.Output | Should -Match '\*\*Overall Status:\*\* FAILURE'
    }
}

Describe 'act workflow execution: all-passing matrix fixtures' {
    BeforeAll {
        $script:TempRepo = New-TempRepo -CaseName 'all-passing'

        # Point this test case's workflow copy at the all-passing fixtures
        # instead of fixtures/matrix, leaving fixtures/matrix (and the unit
        # tests that depend on it) untouched.
        $workflowPath = Join-Path $TempRepo '.github/workflows/test-results-aggregator.yml'
        (Get-Content -LiteralPath $workflowPath -Raw) `
            -replace 'RESULTS_PATH: fixtures/matrix', 'RESULTS_PATH: fixtures/all-passing' |
            Set-Content -LiteralPath $workflowPath -NoNewline

        $script:Result = Invoke-ActCase -CaseName 'all-passing' -TempRepo $TempRepo
    }

    AfterAll {
        Remove-Item -LiteralPath $TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exits with code 0' {
        $Result.ExitCode | Should -Be 0
    }

    It 'shows both jobs succeeding' {
        ($Result.Output | Select-String -Pattern 'Job succeeded' -AllMatches).Matches.Count | Should -Be 2
    }

    It 'reports the exact expected aggregate totals' {
        $Result.Output | Should -Match '\| Total \| 4 \|'
        $Result.Output | Should -Match '\| Passed \| 4 \|'
        $Result.Output | Should -Match '\| Failed \| 0 \|'
        $Result.Output | Should -Match '\| Skipped \| 0 \|'
        $Result.Output | Should -Match '\| Duration \(s\) \| 0\.75 \|'
    }

    It 'reports no flaky tests and overall SUCCESS' {
        $Result.Output | Should -Match 'No flaky tests detected\.'
        $Result.Output | Should -Match '\*\*Overall Status:\*\* SUCCESS'
    }
}

AfterAll {
    (Test-Path -LiteralPath $ActResultPath) | Out-Null
}
