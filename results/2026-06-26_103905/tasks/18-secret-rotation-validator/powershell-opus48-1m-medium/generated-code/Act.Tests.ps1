#requires -Modules Pester

# End-to-end test harness: EVERY test case is exercised through the GitHub Actions
# workflow via `act` (nektos/act), never by calling the script directly.
#
# For each case we:
#   1. Build an isolated temp git repo containing the project files + that case's
#      fixture committed as secrets.json (the path the workflow's CONFIG_PATH points at).
#   2. Run `act push --rm`, capturing combined stdout/stderr.
#   3. Append the run's output to act-result.txt (clearly delimited per case).
#   4. Assert act exited 0.
#   5. Assert every job reported "Job succeeded".
#   6. Parse the output and assert on EXACT expected values for that fixture.

BeforeAll {
    $script:Root      = $PSScriptRoot
    $script:ResultLog = Join-Path $PSScriptRoot 'act-result.txt'

    # Start with a fresh aggregate log for this harness run.
    Set-Content -LiteralPath $script:ResultLog -Value "act test harness results`n" -Encoding utf8

    # Files copied into every per-case temp repo.
    $script:ProjectFiles = @(
        'SecretRotationValidator.ps1',
        'SecretRotationValidator.Tests.ps1',
        '.actrc'
    )

    # Build an isolated git repo for a case and run act against it once.
    function Invoke-ActCase {
        param(
            [Parameter(Mandatory)][string]$CaseName,
            [Parameter(Mandatory)][string]$FixtureFile
        )

        $work = Join-Path ([System.IO.Path]::GetTempPath()) "srv-act-$CaseName-$PID"
        if (Test-Path $work) { Remove-Item -Recurse -Force $work }
        New-Item -ItemType Directory -Path $work | Out-Null

        # Copy project files.
        foreach ($f in $script:ProjectFiles) {
            Copy-Item -LiteralPath (Join-Path $script:Root $f) -Destination (Join-Path $work $f)
        }
        # Copy the workflow.
        New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Root '.github/workflows/secret-rotation-validator.yml') `
                  -Destination (Join-Path $work '.github/workflows/secret-rotation-validator.yml')
        # The case fixture becomes the repo's secrets.json (CONFIG_PATH default).
        Copy-Item -LiteralPath (Join-Path $script:Root "fixtures/$FixtureFile") `
                  -Destination (Join-Path $work 'secrets.json')

        # act requires a committed git repo for the push event / checkout.
        Push-Location $work
        try {
            git init -q 2>&1 | Out-Null
            git config user.email 'ci@example.com' 2>&1 | Out-Null
            git config user.name  'ci' 2>&1 | Out-Null
            git add -A 2>&1 | Out-Null
            git commit -q -m "case $CaseName" 2>&1 | Out-Null

            $output = & act push --rm 2>&1 | Out-String
            $exit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Append delimited output to the aggregate log.
        $delim = "=" * 70
        Add-Content -LiteralPath $script:ResultLog -Value @"
$delim
TEST CASE: $CaseName  (fixture: $FixtureFile)
act exit code: $exit
$delim
$output
"@

        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

        return [pscustomobject]@{ ExitCode = $exit; Output = $output }
    }

    # Run all three cases up front (act is slow; one invocation per case).
    $script:Cases = @{
        mixed       = Invoke-ActCase -CaseName 'mixed'       -FixtureFile 'case-mixed.json'
        all_ok      = Invoke-ActCase -CaseName 'all-ok'      -FixtureFile 'case-all-ok.json'
        all_expired = Invoke-ActCase -CaseName 'all-expired' -FixtureFile 'case-all-expired.json'
    }
}

Describe 'act: case mixed (1 expired, 1 warning, 1 ok)' {
    BeforeAll { $script:R = $script:Cases.mixed }

    It 'act exits 0' { $script:R.ExitCode | Should -Be 0 }

    It 'both jobs report Job succeeded' {
        ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'unit tests pass inside the pipeline' {
        $script:R.Output | Should -Match 'All 17 unit tests passed'
    }

    It 'emits the exact rotation summary line' {
        $script:R.Output | Should -Match 'ROTATION_SUMMARY expired=1 warning=1 ok=1 total=3'
    }

    It 'markdown summary shows exact per-urgency counts' {
        $script:R.Output | Should -Match '- Expired: 1'
        $script:R.Output | Should -Match '- Warning: 1'
        $script:R.Output | Should -Match '- Ok: 1'
        $script:R.Output | Should -Match '- Total: 3'
    }

    It 'classifies each secret into the correct group with exact figures' {
        # db-password expired at -86 days, api-key warning at +4, tls-cert ok at +65
        $script:R.Output | Should -Match 'db-password \| 2026-01-01 \| 90 \| 2026-04-01 \| -86 \| api, worker'
        $script:R.Output | Should -Match 'api-key \| 2026-04-01 \| 90 \| 2026-06-30 \| 4 \| gateway'
        $script:R.Output | Should -Match 'tls-cert \| 2026-06-01 \| 90 \| 2026-08-30 \| 65 \| web'
    }
}

Describe 'act: case all-ok (0 expired, 0 warning, 2 ok)' {
    BeforeAll { $script:R = $script:Cases.all_ok }

    It 'act exits 0' { $script:R.ExitCode | Should -Be 0 }

    It 'both jobs report Job succeeded' {
        ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'emits the exact rotation summary line' {
        $script:R.Output | Should -Match 'ROTATION_SUMMARY expired=0 warning=0 ok=2 total=2'
    }

    It 'reports no expired or warning secrets in markdown' {
        $script:R.Output | Should -Match '- Expired: 0'
        $script:R.Output | Should -Match '- Warning: 0'
        $script:R.Output | Should -Match '- Ok: 2'
    }
}

Describe 'act: case all-expired (2 expired, 0 warning, 0 ok)' {
    BeforeAll { $script:R = $script:Cases.all_expired }

    It 'act exits 0' { $script:R.ExitCode | Should -Be 0 }

    It 'both jobs report Job succeeded' {
        ([regex]::Matches($script:R.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
    }

    It 'emits the exact rotation summary line' {
        $script:R.Output | Should -Match 'ROTATION_SUMMARY expired=2 warning=0 ok=0 total=2'
    }

    It 'lists both expired secrets by name' {
        $script:R.Output | Should -Match 'legacy-key'
        $script:R.Output | Should -Match 'old-cert'
        $script:R.Output | Should -Match '- Expired: 2'
    }
}

Describe 'act-result.txt artifact' {
    It 'exists and contains all three delimited cases' {
        Test-Path -LiteralPath $script:ResultLog | Should -BeTrue
        $log = Get-Content -LiteralPath $script:ResultLog -Raw
        $log | Should -Match 'TEST CASE: mixed'
        $log | Should -Match 'TEST CASE: all-ok'
        $log | Should -Match 'TEST CASE: all-expired'
    }
}
