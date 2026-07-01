#Requires -Modules Pester
<#
    Drives the ACTUAL GitHub Actions workflow through `act`, in Docker, so
    every functional test case runs through the real pipeline rather than
    being called directly. This is the one test file in the suite that
    invokes `act push` -- everything else either tests the module/CLI
    directly (run *inside* the container as the workflow's own unit-tests
    job) or performs static analysis of the workflow file on the host.

    The workflow's "cleanup" job runs as a 4-way build matrix (age-policy,
    size-policy, keep-latest, combined-dry-run), so a SINGLE `act push`
    invocation exercises all four functional test cases plus the unit-tests
    job in one pass -- five jobs total, each independently asserted below.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ActResultPath = Join-Path $script:RepoRoot 'act-result.txt'

    $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-cleanup-act-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempRepo | Out-Null

    foreach ($item in @('.actrc', '.github', 'tests', 'fixtures', 'ArtifactCleanup.psm1', 'Invoke-ArtifactCleanup.ps1')) {
        Copy-Item -Path (Join-Path $script:RepoRoot $item) -Destination (Join-Path $script:TempRepo $item) -Recurse
    }

    Push-Location $script:TempRepo
    try {
        & git init -q
        & git -c user.name='act-harness' -c user.email='act-harness@example.com' add -A
        & git -c user.name='act-harness' -c user.email='act-harness@example.com' commit -q -m 'act pipeline test commit'

        # --pull=false: the benchmark image (act-ubuntu-pwsh:latest) only exists
        # locally; act's default force-pull otherwise fails with a registry
        # auth error even though the image is already present.
        $script:RawOutput = & act push --rm --pull=false 2>&1 | Out-String
        $script:ActExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $header = @"
================================================================================
TEST CASE: full pipeline (single act push, 4-scenario build matrix + unit tests)
Command: act push --rm --pull=false
Exit code: $script:ActExitCode
================================================================================
"@
    Set-Content -Path $script:ActResultPath -Value $header
    Add-Content -Path $script:ActResultPath -Value $script:RawOutput

    function script:Get-ScenarioLine([string] $Scenario) {
        ($script:RawOutput -split "`n" | Select-String -SimpleMatch "SCENARIO=$Scenario ").Line | Select-Object -First 1
    }
}

AfterAll {
    if (Test-Path $script:TempRepo) {
        Remove-Item -Path $script:TempRepo -Recurse -Force
    }
}

Describe 'Artifact cleanup workflow executed via act' {

    It 'produces the act-result.txt artifact' {
        Test-Path $script:ActResultPath | Should -Be $true
    }

    It 'exits with code 0' {
        $script:ActExitCode | Should -Be 0
    }

    It 'reports "Job succeeded" for all 5 jobs (1 unit-tests + 4 matrix scenarios)' {
        $successCount = ([regex]::Matches($script:RawOutput, 'Job succeeded')).Count
        $successCount | Should -Be 5
    }

    It 'reports no "Job failed" anywhere in the run' {
        $script:RawOutput | Should -Not -Match 'Job failed'
    }

    It 'runs the 19 Pester unit tests inside the container and they all pass' {
        # Match the plain (non-ANSI-colored) summary line our own workflow
        # step prints, rather than Pester's colorized console output, whose
        # embedded ANSI escape codes make substring matching brittle.
        $script:RawOutput | Should -Match 'All 19 unit tests passed\.'
    }

    Context 'Scenario: age-policy (MaxAgeDays=30)' {
        It 'reports exactly the hand-computed expected values' {
            $line = Get-ScenarioLine 'age-policy'
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match 'DRYRUN=False'
            $line | Should -Match 'RETAINED=4'
            $line | Should -Match 'DELETED=4'
            $line | Should -Match 'RECLAIMED_BYTES=796917760'
            $line | Should -Match 'TOTAL_BYTES=1321205760'
        }
    }

    Context 'Scenario: size-policy (MaxTotalSizeMB=900)' {
        It 'reports exactly the hand-computed expected values' {
            $line = Get-ScenarioLine 'size-policy'
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match 'DRYRUN=False'
            $line | Should -Match 'RETAINED=5'
            $line | Should -Match 'DELETED=3'
            $line | Should -Match 'RECLAIMED_BYTES=482344960'
        }
    }

    Context 'Scenario: keep-latest (KeepLatestN=2)' {
        It 'reports exactly the hand-computed expected values' {
            $line = Get-ScenarioLine 'keep-latest'
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match 'DRYRUN=False'
            $line | Should -Match 'RETAINED=4'
            $line | Should -Match 'DELETED=4'
            $line | Should -Match 'RECLAIMED_BYTES=692060160'
        }
    }

    Context 'Scenario: combined-dry-run (MaxAgeDays=30, KeepLatestN=2, MaxTotalSizeMB=1000, DryRun)' {
        It 'reports exactly the hand-computed expected values and DRYRUN=True' {
            $line = Get-ScenarioLine 'combined-dry-run'
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match 'DRYRUN=True'
            $line | Should -Match 'RETAINED=3'
            $line | Should -Match 'DELETED=5'
            $line | Should -Match 'RECLAIMED_BYTES=1006632960'
        }
    }
}
