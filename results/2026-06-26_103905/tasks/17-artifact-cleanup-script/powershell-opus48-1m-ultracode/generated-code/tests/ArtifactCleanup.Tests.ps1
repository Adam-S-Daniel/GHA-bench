# ArtifactCleanup.Tests.ps1
#
# Pester unit tests for the artifact-cleanup retention engine, written using
# red/green TDD. Each Describe block targets one piece of behaviour:
#   - module loading / public surface
#   - the "no policy" baseline
#   - each individual retention policy (max-age, keep-latest-N, max-total-size)
#   - policy interaction / precedence
#   - the summary maths (space reclaimed, counts)
#   - dry-run vs live execution
#   - input validation / graceful error handling
#
# Run with:  Invoke-Pester ./tests/ArtifactCleanup.Tests.ps1

BeforeAll {
    # Resolve the module relative to the repo root (the tests live in ./tests).
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ArtifactCleanup.psm1'
    Import-Module $script:ModulePath -Force

    # A fixed "now" so every age-based assertion is deterministic.
    $script:Now = [datetime]::new(2026, 06, 28, 0, 0, 0, [System.DateTimeKind]::Utc)

    # Small helper to build artifact objects without repeating boilerplate.
    function New-TestArtifact {
        param(
            [string]   $Name,
            [long]     $SizeBytes,
            [datetime] $CreatedAt,
            [string]   $WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
        }
    }
}

Describe 'Module surface' {
    It 'exports Get-ArtifactCleanupPlan' {
        Get-Command Get-ArtifactCleanupPlan -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'exports Invoke-ArtifactCleanup' {
        Get-Command Invoke-ArtifactCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Baseline: no policies configured' {
    It 'retains every artifact and deletes nothing' {
        $artifacts = @(
            New-TestArtifact 'a' 100 $script:Now.AddDays(-400) '1'
            New-TestArtifact 'b' 200 $script:Now.AddDays(-10)  '1'
            New-TestArtifact 'c' 300 $script:Now.AddDays(-1)   '2'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -Now $script:Now

        $plan.Summary.TotalArtifacts      | Should -Be 3
        $plan.Summary.RetainedCount       | Should -Be 3
        $plan.Summary.DeletedCount        | Should -Be 0
        $plan.Summary.SpaceReclaimedBytes | Should -Be 0
        $plan.Summary.TotalSizeBytes      | Should -Be 600
        $plan.Summary.RetainedSizeBytes   | Should -Be 600
    }
}

Describe 'Policy: max-age' {
    It 'deletes artifacts older than the cutoff and keeps the rest' {
        # Now = 2026-06-28, MaxAgeDays = 30 => cutoff = 2026-05-29.
        $artifacts = @(
            New-TestArtifact 'old-jan'  1000 ([datetime]'2026-01-01Z') '1'   # delete
            New-TestArtifact 'old-mar'  2000 ([datetime]'2026-03-01Z') '1'   # delete
            New-TestArtifact 'jun-01'    500 ([datetime]'2026-06-01Z') '2'   # keep (after cutoff)
            New-TestArtifact 'jun-27'    300 ([datetime]'2026-06-27Z') '2'   # keep
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

        $plan.Summary.DeletedCount        | Should -Be 2
        $plan.Summary.RetainedCount       | Should -Be 2
        $plan.Summary.SpaceReclaimedBytes | Should -Be 3000
        ($plan.Deleted.Name | Sort-Object) | Should -Be @('old-jan', 'old-mar')
        $plan.Deleted | ForEach-Object { $_.Reason | Should -Be 'MaxAge' }
    }

    It 'treats the cutoff boundary as inclusive of "keep" (younger-than is kept)' {
        # An artifact created exactly at the cutoff is NOT older-than, so kept.
        $atCutoff = $script:Now.AddDays(-30)
        $artifacts = @(
            New-TestArtifact 'edge'  100 $atCutoff           '1'
            New-TestArtifact 'older' 100 $atCutoff.AddSeconds(-1) '1'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

        $plan.Retained.Name | Should -Be 'edge'
        $plan.Deleted.Name  | Should -Be 'older'
    }
}

Describe 'Policy: keep-latest-N per workflow' {
    It 'keeps only the newest N artifacts in each workflow group' {
        $artifacts = @(
            # Workflow 1: four artifacts, keep the two newest.
            New-TestArtifact 'w1-a' 10 ([datetime]'2026-06-01Z') '1'   # delete
            New-TestArtifact 'w1-b' 10 ([datetime]'2026-06-02Z') '1'   # delete
            New-TestArtifact 'w1-c' 10 ([datetime]'2026-06-03Z') '1'   # keep
            New-TestArtifact 'w1-d' 10 ([datetime]'2026-06-04Z') '1'   # keep
            # Workflow 2: only one artifact, always kept.
            New-TestArtifact 'w2-a' 10 ([datetime]'2026-01-01Z') '2'   # keep
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 2 -Now $script:Now

        $plan.Summary.DeletedCount  | Should -Be 2
        $plan.Summary.RetainedCount | Should -Be 3
        ($plan.Deleted.Name  | Sort-Object) | Should -Be @('w1-a', 'w1-b')
        ($plan.Retained.Name | Sort-Object) | Should -Be @('w1-c', 'w1-d', 'w2-a')
        $plan.Deleted | ForEach-Object { $_.Reason | Should -Be 'KeepLatestN' }
    }

    It 'keeps everything when N is larger than the group size' {
        $artifacts = @(
            New-TestArtifact 'only-a' 10 ([datetime]'2026-06-01Z') '1'
            New-TestArtifact 'only-b' 10 ([datetime]'2026-06-02Z') '1'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 5 -Now $script:Now

        $plan.Summary.DeletedCount | Should -Be 0
        $plan.Summary.RetainedCount | Should -Be 2
    }
}

Describe 'Policy: max-total-size' {
    It 'evicts oldest-first until the retained total fits the budget' {
        # Total = 4000; budget = 2500 => must drop >=1500 oldest-first.
        $artifacts = @(
            New-TestArtifact 'oldest'  1000 ([datetime]'2026-01-01Z') '1'  # delete (then 3000)
            New-TestArtifact 'older'   1000 ([datetime]'2026-02-01Z') '1'  # delete (then 2000 <= 2500)
            New-TestArtifact 'newer'   1000 ([datetime]'2026-03-01Z') '1'  # keep
            New-TestArtifact 'newest'  1000 ([datetime]'2026-04-01Z') '1'  # keep
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 2500 -Now $script:Now

        $plan.Summary.DeletedCount        | Should -Be 2
        $plan.Summary.RetainedSizeBytes   | Should -Be 2000
        $plan.Summary.SpaceReclaimedBytes | Should -Be 2000
        ($plan.Deleted.Name | Sort-Object) | Should -Be @('older', 'oldest')
        $plan.Deleted | ForEach-Object { $_.Reason | Should -Be 'MaxTotalSize' }
        $plan.Summary.OverBudget | Should -BeFalse
    }

    It 'does nothing when already within budget' {
        $artifacts = @(
            New-TestArtifact 'a' 500 ([datetime]'2026-01-01Z') '1'
            New-TestArtifact 'b' 500 ([datetime]'2026-02-01Z') '1'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 5000 -Now $script:Now

        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Policy interaction & precedence' {
    It 'protects the newest-N from max-age (protection floor wins)' {
        # keep-latest-N=1 protects the newest per workflow even though it is old.
        $artifacts = @(
            New-TestArtifact 'w1-old'    100 ([datetime]'2026-01-01Z') 'W1'  # beyond N -> KeepLatestN delete
            New-TestArtifact 'w1-newest' 100 ([datetime]'2026-01-15Z') 'W1'  # newest, old, but PROTECTED -> keep
            New-TestArtifact 'w2-recent' 100 ([datetime]'2026-06-27Z') 'W2'  # newest, recent -> keep
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 1 -MaxAgeDays 30 -Now $script:Now

        $plan.Summary.DeletedCount  | Should -Be 1
        $plan.Summary.RetainedCount | Should -Be 2
        $plan.Deleted.Name          | Should -Be 'w1-old'
        ($plan.Retained.Name | Sort-Object) | Should -Be @('w1-newest', 'w2-recent')
        # The retained 'w1-newest' is old but survived because it is protected.
        ($plan.Retained | Where-Object Name -eq 'w1-newest').Protected | Should -BeTrue
    }

    It 'reports OverBudget when protected artifacts alone exceed the size budget' {
        # keep-latest-N=2 protects both (total 2000) but budget is only 1000.
        $artifacts = @(
            New-TestArtifact 'p1' 1000 ([datetime]'2026-06-01Z') '1'
            New-TestArtifact 'p2' 1000 ([datetime]'2026-06-02Z') '1'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 2 -MaxTotalSizeBytes 1000 -Now $script:Now

        $plan.Summary.DeletedCount | Should -Be 0
        $plan.Summary.OverBudget   | Should -BeTrue
    }
}

Describe 'Dry-run vs live execution (Invoke-ArtifactCleanup)' {
    BeforeEach {
        $script:artifacts = @(
            New-TestArtifact 'old' 100 ([datetime]'2026-01-01Z') '1'
            New-TestArtifact 'new' 100 ([datetime]'2026-06-27Z') '1'
        )
    }

    It 'does NOT invoke the delete action in dry-run mode' {
        $script:deleted = @()
        $action = { param($a) $script:deleted += $a.Name }

        $result = Invoke-ArtifactCleanup -Artifacts $script:artifacts -MaxAgeDays 30 `
            -Now $script:Now -DryRun -DeleteAction $action

        $result.DryRun   | Should -BeTrue
        $result.Executed | Should -BeFalse
        $script:deleted.Count | Should -Be 0          # nothing was actually deleted
        $result.Summary.DeletedCount | Should -Be 1   # but the plan still lists it
    }

    It 'invokes the delete action once per artifact in live mode' {
        $script:deleted = @()
        $action = { param($a) $script:deleted += $a.Name }

        $result = Invoke-ArtifactCleanup -Artifacts $script:artifacts -MaxAgeDays 30 `
            -Now $script:Now -DeleteAction $action

        $result.DryRun   | Should -BeFalse
        $result.Executed | Should -BeTrue
        $script:deleted  | Should -Be @('old')
    }
}

Describe 'Edge cases & error handling' {
    It 'handles an empty artifact list gracefully' {
        $plan = Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays 30 -Now $script:Now
        $plan.Summary.TotalArtifacts      | Should -Be 0
        $plan.Summary.DeletedCount        | Should -Be 0
        $plan.Summary.SpaceReclaimedBytes | Should -Be 0
    }

    It 'accepts ISO-8601 string dates (as produced by JSON fixtures)' {
        $artifacts = @(
            [pscustomobject]@{ Name = 'old'; SizeBytes = 100; CreatedAt = '2026-01-01T00:00:00Z'; WorkflowRunId = '1' }
            [pscustomobject]@{ Name = 'new'; SizeBytes = 100; CreatedAt = '2026-06-27T00:00:00Z'; WorkflowRunId = '1' }
        )
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now
        $plan.Deleted.Name | Should -Be 'old'
    }

    It 'throws a meaningful error when a required field is missing' {
        $bad = @([pscustomobject]@{ Name = 'x'; SizeBytes = 100; WorkflowRunId = '1' })  # no CreatedAt
        { Get-ArtifactCleanupPlan -Artifacts $bad -Now $script:Now } |
            Should -Throw -ExpectedMessage "*missing required field 'CreatedAt'*"
    }

    It 'throws a meaningful error for a negative size' {
        $bad = @([pscustomobject]@{ Name = 'x'; SizeBytes = -5; CreatedAt = $script:Now; WorkflowRunId = '1' })
        { Get-ArtifactCleanupPlan -Artifacts $bad -Now $script:Now } |
            Should -Throw -ExpectedMessage '*negative*'
    }

    It 'throws a meaningful error for an unparseable date' {
        $bad = @([pscustomobject]@{ Name = 'x'; SizeBytes = 5; CreatedAt = 'not-a-date'; WorkflowRunId = '1' })
        { Get-ArtifactCleanupPlan -Artifacts $bad -Now $script:Now } |
            Should -Throw -ExpectedMessage '*unparseable*'
    }
}
