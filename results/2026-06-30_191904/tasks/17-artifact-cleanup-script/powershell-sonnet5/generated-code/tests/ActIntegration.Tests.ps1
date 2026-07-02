#Requires -Modules Pester

<#
    Runs the ACTUAL GitHub Actions workflow through `act` in an isolated
    temp git repo and asserts on the real output -- this is the "does the
    pipeline really work" proof that complements the unit tests (which the
    workflow itself runs) and the static structure tests.

    Only ONE `act push` invocation happens here (in BeforeAll), reused by
    every It below, because the workflow already exercises all three
    retention-policy scenarios plus the full unit test suite in a single
    run. This keeps us well under the "at most 3 act push runs" budget.
#>

BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..'
    $script:actResultPath = Join-Path $repoRoot 'act-result.txt'

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-cleanup-act-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # Copy only what the pipeline needs: the module, the CLI entry point,
    # fixtures, tests (the workflow runs ArtifactCleanup.Tests.ps1), the
    # workflow definition itself, and the act runner-image pin.
    foreach ($item in @('ArtifactCleanup.psm1', 'artifact-cleanup.ps1', 'fixtures', 'tests', '.github', '.actrc')) {
        Copy-Item -Path (Join-Path $repoRoot $item) -Destination (Join-Path $tempDir $item) -Recurse
    }

    Push-Location $tempDir
    try {
        git init -q
        git config user.email 'act-harness@example.com'
        git config user.name 'Act Harness'
        git add -A
        git commit -q -m 'act integration test commit'

        # --pull=false: the benchmarking sandbox has no registry credentials
        # and the act-ubuntu-pwsh image is already built locally, so a
        # force-pull would fail even though the image is right there.
        $rawOutput = & act push --rm --pull=false 2>&1
        $script:actExitCode = $LASTEXITCODE
        $script:actOutput = $rawOutput | Out-String
    } finally {
        Pop-Location
    }

    $delimiter = "`n===== ActIntegration.Tests.ps1 run ($([datetime]::Now.ToString('yyyy-MM-ddTHH:mm:ss'))) =====`n"
    Add-Content -LiteralPath $script:actResultPath -Value ($delimiter + $script:actOutput)

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    function Get-ReportSection {
        param([string] $ScenarioName)
        $pattern = "(?s)##### Artifact Cleanup Report: $([regex]::Escape($ScenarioName)) #####(.*?)##### End Report: $([regex]::Escape($ScenarioName)) #####"
        $match = [regex]::Match($script:actOutput, $pattern)
        return $match
    }
}

Describe 'act push runs the workflow end to end' {
    It 'saved output to act-result.txt' {
        Test-Path -LiteralPath $script:actResultPath | Should -Be $true
    }

    It 'exits with code 0' {
        $script:actExitCode | Should -Be 0
    }

    It 'reports Job succeeded for the unit-tests job' {
        $script:actOutput | Should -Match 'Unit tests \(Pester\)\].*Job succeeded'
    }

    It 'reports Job succeeded for the cleanup-simulation job' {
        $script:actOutput | Should -Match 'Retention policy scenarios\].*Job succeeded'
    }

    It 'shows exactly two successful jobs' {
        ([regex]::Matches($script:actOutput, 'Job succeeded')).Count | Should -Be 2
    }
}

Describe 'act output - unit test results (run inside the pipeline)' {
    It 'ran all 25 unit tests with zero failures' {
        $script:actOutput | Should -Match 'Unit tests: 25 passed, 0 failed, 0 skipped\.'
    }
}

Describe 'act output - scenario: age-and-keep-latest (max age + keep-latest-N)' {
    BeforeAll {
        $script:section = (Get-ReportSection -ScenarioName 'age-and-keep-latest').Value
    }

    It 'ran this scenario' {
        $script:section | Should -Not -BeNullOrEmpty
    }

    It 'matches the exact known-good deletion plan' {
        $script:section | Should -Match 'DryRun: False'
        $script:section | Should -Match 'TotalArtifacts: 6'
        $script:section | Should -Match 'Deleted: 2'
        $script:section | Should -Match 'Retained: 4'
        $script:section | Should -Match 'BytesReclaimed: 300000000'
        $script:section | Should -Match 'ArtifactsActuallyRemoved: 2'
    }

    It 'deletes the two artifacts that exceed max age and are not protected by keep-latest-N' {
        $script:section | Should -Match 'build-log-3 \(150000000 bytes, reason: max-age-exceeded\)'
        $script:section | Should -Match 'build-log-4 \(150000000 bytes, reason: max-age-exceeded\)'
    }

    It 'retains a 181-day-old artifact because keep-latest-N protects it' {
        $script:section | Should -Match 'test-report-2 \(50000000 bytes, reason: kept-latest-N\)'
    }
}

Describe 'act output - scenario: size-cap-eviction (max total size)' {
    BeforeAll {
        $script:section = (Get-ReportSection -ScenarioName 'size-cap-eviction').Value
    }

    It 'ran this scenario' {
        $script:section | Should -Not -BeNullOrEmpty
    }

    It 'matches the exact known-good deletion plan' {
        $script:section | Should -Match 'DryRun: False'
        $script:section | Should -Match 'TotalArtifacts: 4'
        $script:section | Should -Match 'Deleted: 2'
        $script:section | Should -Match 'Retained: 2'
        $script:section | Should -Match 'BytesReclaimed: 200000000'
        $script:section | Should -Match 'ArtifactsActuallyRemoved: 2'
    }

    It 'evicts the two oldest artifacts, not the newest' {
        $script:section | Should -Match 'deploy-artifact-3 \(100000000 bytes, reason: max-total-size-exceeded\)'
        $script:section | Should -Match 'deploy-artifact-4 \(100000000 bytes, reason: max-total-size-exceeded\)'
        $script:section | Should -Match 'deploy-artifact-1 \(100000000 bytes, reason: kept-latest-N\)'
        $script:section | Should -Match 'deploy-artifact-2 \(100000000 bytes, reason: within-policy\)'
    }
}

Describe 'act output - scenario: dry-run-mode' {
    BeforeAll {
        $script:section = (Get-ReportSection -ScenarioName 'dry-run-mode').Value
    }

    It 'ran this scenario' {
        $script:section | Should -Not -BeNullOrEmpty
    }

    It 'computes the same deletion plan as the equivalent live run, but removes nothing' {
        $script:section | Should -Match 'DryRun: True'
        $script:section | Should -Match 'Deleted: 2'
        $script:section | Should -Match 'BytesReclaimed: 300000000'
        $script:section | Should -Match 'ArtifactsActuallyRemoved: 0'
    }
}
