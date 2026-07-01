#
# Pester tests for the top-level Invoke-ArtifactCleanup.ps1 entry script
# used directly by the GitHub Actions workflow.
#
BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'Invoke-ArtifactCleanup.ps1'
    $SampleFixture = Join-Path $PSScriptRoot '..' 'fixtures' 'artifacts-sample.json'
}

Describe 'Invoke-ArtifactCleanup.ps1 (entry script)' {
    It 'prints a machine-parseable summary in dry-run mode' {
        # *>&1 merges all streams (Write-Host writes to the Information
        # stream) so the assertions below can inspect every printed line.
        $output = & $ScriptPath -FixturePath $SampleFixture -MaxAgeDays 45 -MaxTotalSizeBytes 999999999999 -KeepLatestN 2 -Now '2026-07-01T00:00:00Z' -DryRun *>&1 | ForEach-Object { $_.ToString() }

        $output | Should -Contain 'DRY_RUN=True'
        $output | Should -Contain 'DELETED_COUNT=1'
        $output | Should -Contain 'RETAINED_COUNT=9'
        $output | Should -Contain 'SPACE_RECLAIMED_BYTES=104857600'
        ($output -match '^\[DRY RUN\] Would delete: ci-build-98').Count | Should -Be 1
    }

    It 'prints DRY_RUN=False and performs deletions when not in dry-run mode' {
        $output = & $ScriptPath -FixturePath $SampleFixture -MaxAgeDays 45 -MaxTotalSizeBytes 999999999999 -KeepLatestN 2 -Now '2026-07-01T00:00:00Z' *>&1 | ForEach-Object { $_.ToString() }

        $output | Should -Contain 'DRY_RUN=False'
        ($output -match '^Deleted: ci-build-98').Count | Should -Be 1
    }

    It 'exits non-zero with a clear error message for a missing fixture' {
        & $ScriptPath -FixturePath 'does-not-exist.json' -MaxAgeDays 45 -MaxTotalSizeBytes 100 -KeepLatestN 1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}
