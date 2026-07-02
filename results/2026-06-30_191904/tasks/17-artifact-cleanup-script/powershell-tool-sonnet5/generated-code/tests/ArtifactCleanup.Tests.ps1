#Requires -Modules Pester
<#
    Unit tests for the artifact retention/cleanup policy engine.
    These are the core "red/green" TDD tests for Get-ArtifactCleanupPlan and
    Format-ArtifactCleanupSummary. They exercise the module in isolation using
    in-memory fixture objects (loaded from fixtures/sample-artifacts.json) so
    every policy combination has a hand-computed expected result.

    This suite is executed inside the GitHub Actions workflow (via act) as
    part of the "unit-tests" job -- see .github/workflows/artifact-cleanup-script.yml
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force

    $fixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'sample-artifacts.json'
    $script:SampleArtifacts = Get-Content -Raw -Path $fixturePath | ConvertFrom-Json

    # Fixed reference time so age-based assertions are deterministic regardless
    # of when the suite actually runs.
    $script:FixedNow = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()
}

Describe 'Get-ArtifactCleanupPlan' {

    Context 'when no policies are specified' {
        It 'retains every artifact and deletes none' {
            $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 8
            $plan.Summary.DeletedCount | Should -Be 0
            $plan.Summary.ReclaimedBytes | Should -Be 0
            $plan.Summary.TotalSizeBytes | Should -Be 1321205760
        }
    }

    Context 'when an empty artifact list is supplied' {
        It 'returns an empty plan without error' {
            $plan = Get-ArtifactCleanupPlan -Artifacts @() -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 0
            $plan.Summary.DeletedCount | Should -Be 0
            $plan.Summary.ReclaimedBytes | Should -Be 0
        }
    }

    Context 'Scenario 1: MaxAgeDays only (age-policy)' {
        It 'deletes artifacts older than the max age and retains the rest' {
            $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxAgeDays 30 -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 4
            $plan.Summary.DeletedCount | Should -Be 4
            $plan.Summary.ReclaimedBytes | Should -Be 796917760

            ($plan.Deleted | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-4', 'ci-build-5', 'deploy-2', 'deploy-3')
            ($plan.Retained | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-1', 'ci-build-2', 'ci-build-3', 'deploy-1')

            ($plan.Deleted | Where-Object Name -eq 'ci-build-4').DeletionReason | Should -Be 'MaxAge'
        }
    }

    Context 'Scenario 2: MaxTotalSizeBytes only (size-policy)' {
        It 'deletes the oldest artifacts first until under the total size budget' {
            $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxTotalSizeBytes (900 * 1MB) -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 5
            $plan.Summary.DeletedCount | Should -Be 3
            $plan.Summary.ReclaimedBytes | Should -Be 482344960

            ($plan.Deleted | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-4', 'ci-build-5', 'deploy-3')
            ($plan.Deleted | Where-Object Name -eq 'ci-build-5').DeletionReason | Should -Be 'MaxTotalSize'
        }
    }

    Context 'Scenario 3: KeepLatestN only (per-workflow retention)' {
        It 'keeps only the N most recent artifacts per workflow and deletes the rest' {
            $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -KeepLatestN 2 -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 4
            $plan.Summary.DeletedCount | Should -Be 4
            $plan.Summary.ReclaimedBytes | Should -Be 692060160

            ($plan.Deleted | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-3', 'ci-build-4', 'ci-build-5', 'deploy-3')
            ($plan.Retained | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-1', 'ci-build-2', 'deploy-1', 'deploy-2')
            ($plan.Deleted | Where-Object Name -eq 'deploy-3').DeletionReason | Should -Be 'KeepLatestN'
        }
    }

    Context 'Scenario 4: combined policies (union semantics) with DryRun' {
        It 'unions every triggered policy reason and reports what WOULD be reclaimed' {
            $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxAgeDays 30 -KeepLatestN 2 `
                -MaxTotalSizeBytes (1000 * 1MB) -DryRun -Now $script:FixedNow

            $plan.Summary.RetainedCount | Should -Be 3
            $plan.Summary.DeletedCount | Should -Be 5
            $plan.Summary.ReclaimedBytes | Should -Be 1006632960
            $plan.Summary.IsDryRun | Should -Be $true

            ($plan.Retained | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-1', 'ci-build-2', 'deploy-1')

            # ci-build-3 is only flagged by KeepLatestN (not age, not size)
            $ci3 = $plan.Deleted | Where-Object Name -eq 'ci-build-3'
            $ci3.DeletionReason | Should -Be 'KeepLatestN'

            # ci-build-5 is flagged by all three policies
            $ci5 = $plan.Deleted | Where-Object Name -eq 'ci-build-5'
            ($ci5.DeletionReason -split ',') | Should -Contain 'MaxAge'
            ($ci5.DeletionReason -split ',') | Should -Contain 'MaxTotalSize'
            ($ci5.DeletionReason -split ',') | Should -Contain 'KeepLatestN'
        }
    }

    Context 'input validation' {
        It 'throws a meaningful error when MaxAgeDays is negative' {
            { Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxAgeDays -1 -Now $script:FixedNow } |
                Should -Throw '*MaxAgeDays*'
        }

        It 'throws a meaningful error when MaxTotalSizeBytes is negative' {
            { Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxTotalSizeBytes -1 -Now $script:FixedNow } |
                Should -Throw '*MaxTotalSizeBytes*'
        }

        It 'throws a meaningful error when KeepLatestN is negative' {
            { Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -KeepLatestN -1 -Now $script:FixedNow } |
                Should -Throw '*KeepLatestN*'
        }

        It 'throws a meaningful error when an artifact is missing a required field' {
            $badArtifacts = @([pscustomobject]@{ Name = 'no-size'; CreatedAt = '2026-06-01T00:00:00Z'; WorkflowName = 'CI' })
            { Get-ArtifactCleanupPlan -Artifacts $badArtifacts -Now $script:FixedNow } |
                Should -Throw '*SizeBytes*'
        }
    }
}

Describe 'Format-ArtifactCleanupSummary' {
    It 'produces a machine-parseable single-line summary' {
        $plan = Get-ArtifactCleanupPlan -Artifacts $script:SampleArtifacts -MaxAgeDays 30 -Now $script:FixedNow
        $line = Format-ArtifactCleanupSummary -Plan $plan -ScenarioName 'age-policy'

        $line | Should -Match 'SCENARIO=age-policy'
        $line | Should -Match 'RETAINED=4'
        $line | Should -Match 'DELETED=4'
        $line | Should -Match 'RECLAIMED_BYTES=796917760'
        $line | Should -Match 'DRYRUN=False'
    }
}
