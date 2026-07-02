<#
    Runs the actual GitHub Actions workflow through `act` and asserts on the
    exact expected values in its output. This is the canonical end-to-end
    test: every other Pester test exercises the PowerShell code directly,
    but this one proves the same code behaves correctly inside the
    published CI pipeline.

    Output is appended to act-result.txt (repo root) with a clear delimiter,
    as required by the benchmark harness.
#>

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:resultFile = Join-Path $repoRoot 'act-result.txt'
}

Describe 'act push --rm (secret-rotation-validator.yml)' {

    It 'runs the workflow via act, exits 0, and produces the exact expected report values' {
        Push-Location $script:repoRoot
        try {
            $output = & act push --rm --pull=false 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        $delimiter = "===== act push --rm (run: $(Get-Date -Format o)) ====="
        Add-Content -Path $script:resultFile -Value $delimiter
        Add-Content -Path $script:resultFile -Value ($output -join "`n")
        Add-Content -Path $script:resultFile -Value "===== exit code: $exitCode ====="

        $joined = $output -join "`n"

        # act itself must exit 0.
        $exitCode | Should -Be 0

        # Both jobs must report success.
        ($joined | Select-String -Pattern 'Job succeeded' -AllMatches).Matches.Count | Should -Be 2

        # 'test' job: exact Pester summary line from inside the container.
        $joined | Should -Match 'Tests Passed: 16, .*Failed: 0'

        # 'validate-rotation' job: healthy fixture reports all-Ok summary.
        $joined | Should -Match 'Expired: 0 \| Warning: 0 \| Ok: 1 \| Total: 1'
        $joined | Should -Match 'healthy-secret \| Ok'

        # 'validate-rotation' job: mixed fixture reports exact expired secret and summary counts.
        $joined | Should -Match '"Name": "db-password"'
        $joined | Should -Match '"Status": "Expired"'
        $joined | Should -Match '"ExpiredCount": 1'
        $joined | Should -Match '"WarningCount": 0'
        $joined | Should -Match '"OkCount": 2'
        $joined | Should -Match '"TotalCount": 3'

        # The intentionally-failing mixed-secrets step must have failed, and the
        # subsequent assertion step must have detected that failure correctly.
        $joined | Should -Match 'Mixed-secrets check correctly flagged expired/warning secrets \(outcome: failure\)'
    }
}
