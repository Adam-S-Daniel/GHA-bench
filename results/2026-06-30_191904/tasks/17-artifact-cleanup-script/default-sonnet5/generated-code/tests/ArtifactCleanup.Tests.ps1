# Pester tests for the Artifact Cleanup retention engine.
# TDD note: this file is built incrementally -- each Describe block below was
# added only after being run red (module/function missing) and then made to
# pass with the minimum code in ../src/ArtifactCleanup.psm1.

BeforeAll {
    Import-Module "$PSScriptRoot/../src/ArtifactCleanup.psm1" -Force
}

Describe 'Get-ProtectedArtifactIds' {

    It 'protects the latest N runs worth of artifacts per workflow' {
        $artifacts = @(
            [PSCustomObject]@{ Id='ci-3'; Name='build'; SizeBytes=100; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r3' }
            [PSCustomObject]@{ Id='ci-2'; Name='build'; SizeBytes=100; CreatedAt=[datetime]'2026-06-25'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='ci-1'; Name='build'; SizeBytes=100; CreatedAt=[datetime]'2026-06-10'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $protected = Get-ProtectedArtifactIds -Artifacts $artifacts -KeepLatestN 2

        $protected | Should -Contain 'ci-3'
        $protected | Should -Contain 'ci-2'
        $protected | Should -Not -Contain 'ci-1'
        $protected.Count | Should -Be 2
    }

    It 'returns an empty set when KeepLatestN is 0' {
        $artifacts = @(
            [PSCustomObject]@{ Id='a'; Name='x'; SizeBytes=1; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $protected = Get-ProtectedArtifactIds -Artifacts $artifacts -KeepLatestN 0

        $protected.Count | Should -Be 0
    }

    It 'keeps or drops all artifacts of a single run together' {
        # A single run can publish more than one artifact (e.g. logs + build
        # output). Keep-latest-N must protect the whole run, not just one
        # artifact from it.
        $artifacts = @(
            [PSCustomObject]@{ Id='new-log'; Name='log'; SizeBytes=1; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='new-bin'; Name='bin'; SizeBytes=1; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='old-log'; Name='log'; SizeBytes=1; CreatedAt=[datetime]'2026-06-01'; WorkflowName='CI'; WorkflowRunId='r1' }
            [PSCustomObject]@{ Id='old-bin'; Name='bin'; SizeBytes=1; CreatedAt=[datetime]'2026-06-01'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $protected = Get-ProtectedArtifactIds -Artifacts $artifacts -KeepLatestN 1

        $protected.Count | Should -Be 2
        $protected | Should -Contain 'new-log'
        $protected | Should -Contain 'new-bin'
    }
}

Describe 'Get-ExpiredArtifactIds' {

    It 'returns unprotected artifacts older than MaxAgeDays relative to Now' {
        $now = [datetime]'2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Id='young'; Name='a'; SizeBytes=1; CreatedAt=[datetime]'2026-06-25'; WorkflowName='CI'; WorkflowRunId='r1' }
            [PSCustomObject]@{ Id='old'; Name='a'; SizeBytes=1; CreatedAt=[datetime]'2026-05-01'; WorkflowName='CI'; WorkflowRunId='r2' }
        )

        $expired = Get-ExpiredArtifactIds -Artifacts $artifacts -MaxAgeDays 30 -Now $now -ProtectedIds @()

        $expired | Should -Contain 'old'
        $expired | Should -Not -Contain 'young'
    }

    It 'never expires a protected artifact regardless of age' {
        $now = [datetime]'2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Id='old-protected'; Name='a'; SizeBytes=1; CreatedAt=[datetime]'2026-01-01'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $expired = Get-ExpiredArtifactIds -Artifacts $artifacts -MaxAgeDays 30 -Now $now -ProtectedIds @('old-protected')

        $expired | Should -Not -Contain 'old-protected'
        $expired.Count | Should -Be 0
    }
}

Describe 'Get-SizeBudgetArtifactIds' {

    It 'evicts the oldest unprotected survivors first until under budget' {
        $artifacts = @(
            [PSCustomObject]@{ Id='newest'; Name='a'; SizeBytes=100; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r3' }
            [PSCustomObject]@{ Id='middle'; Name='a'; SizeBytes=100; CreatedAt=[datetime]'2026-06-15'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='oldest'; Name='a'; SizeBytes=100; CreatedAt=[datetime]'2026-06-01'; WorkflowName='CI'; WorkflowRunId='r1' }
        )
        # Survivors total 300 bytes; budget is 250, so only the single oldest
        # unprotected survivor needs to be evicted to reach 200 <= 250.
        $evicted = Get-SizeBudgetArtifactIds -Artifacts $artifacts -MaxTotalSizeBytes 250 -ProtectedIds @()

        $evicted | Should -Contain 'oldest'
        $evicted.Count | Should -Be 1
    }

    It 'never evicts a protected artifact even if the budget cannot be met' {
        $artifacts = @(
            [PSCustomObject]@{ Id='protected-big'; Name='a'; SizeBytes=1000; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $evicted = Get-SizeBudgetArtifactIds -Artifacts $artifacts -MaxTotalSizeBytes 10 -ProtectedIds @('protected-big')

        $evicted.Count | Should -Be 0
    }

    It 'evicts nothing when already within budget' {
        $artifacts = @(
            [PSCustomObject]@{ Id='a'; Name='a'; SizeBytes=10; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r1' }
        )

        $evicted = Get-SizeBudgetArtifactIds -Artifacts $artifacts -MaxTotalSizeBytes 1000 -ProtectedIds @()

        $evicted.Count | Should -Be 0
    }
}

Describe 'New-RetentionPlan' {

    BeforeAll {
        # Hand-computed scenario combining all three policies:
        #   Now = 2026-07-01, MaxAgeDays=30 (cutoff 2026-06-01), KeepLatestN=2,
        #   MaxTotalSizeBytes=350,000,000
        # CI: build-5 (1d old, protected), build-4 (6d old, protected),
        #     build-3 (21d old, unprotected+young), build-2 (42d, expires),
        #     build-1 (61d, expires)
        # Release: release-3 (3d, protected), release-2 (16d, protected),
        #     release-1 (91d, expires)
        # After age+keep-latest: retained = build-5,build-4,build-3,release-3,release-2 (400MB)
        # Size budget (350MB) evicts oldest unprotected survivor: build-3 (100MB) -> 300MB
        # Final: retained=4 (300,000,000 bytes), deleted=4 (350,000,000 bytes)
        $script:mixedArtifacts = @(
            [PSCustomObject]@{ Id='build-5'; Name='build'; SizeBytes=100000000; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='ci-5' }
            [PSCustomObject]@{ Id='build-4'; Name='build'; SizeBytes=100000000; CreatedAt=[datetime]'2026-06-25'; WorkflowName='CI'; WorkflowRunId='ci-4' }
            [PSCustomObject]@{ Id='build-3'; Name='build'; SizeBytes=100000000; CreatedAt=[datetime]'2026-06-10'; WorkflowName='CI'; WorkflowRunId='ci-3' }
            [PSCustomObject]@{ Id='build-2'; Name='build'; SizeBytes=100000000; CreatedAt=[datetime]'2026-05-20'; WorkflowName='CI'; WorkflowRunId='ci-2' }
            [PSCustomObject]@{ Id='build-1'; Name='build'; SizeBytes=100000000; CreatedAt=[datetime]'2026-05-01'; WorkflowName='CI'; WorkflowRunId='ci-1' }
            [PSCustomObject]@{ Id='release-3'; Name='release'; SizeBytes=50000000; CreatedAt=[datetime]'2026-06-28'; WorkflowName='Release'; WorkflowRunId='rel-3' }
            [PSCustomObject]@{ Id='release-2'; Name='release'; SizeBytes=50000000; CreatedAt=[datetime]'2026-06-15'; WorkflowName='Release'; WorkflowRunId='rel-2' }
            [PSCustomObject]@{ Id='release-1'; Name='release'; SizeBytes=50000000; CreatedAt=[datetime]'2026-04-01'; WorkflowName='Release'; WorkflowRunId='rel-1' }
        )
    }

    It 'combines keep-latest-N, max-age, and max-size policies correctly' {
        $plan = New-RetentionPlan -Artifacts $script:mixedArtifacts -MaxAgeDays 30 -MaxTotalSizeBytes 350000000 -KeepLatestN 2 -Now ([datetime]'2026-07-01')

        $plan.TotalArtifactCount | Should -Be 8
        $plan.RetainedCount | Should -Be 4
        $plan.DeletedCount | Should -Be 4
        $plan.ReclaimedBytes | Should -Be 350000000
        $plan.TotalSizeBytesAfter | Should -Be 300000000

        ($plan.RetainedArtifacts.Id | Sort-Object) | Should -Be @('build-4', 'build-5', 'release-2', 'release-3')
        ($plan.DeletedArtifacts.Id | Sort-Object) | Should -Be @('build-1', 'build-2', 'build-3', 'release-1')
    }

    It 'produces zero deletions when everything is young, small, and within keep-latest-N' {
        $artifacts = @(
            [PSCustomObject]@{ Id='doc-1'; Name='docs'; SizeBytes=5000000; CreatedAt=[datetime]'2026-06-29'; WorkflowName='Docs'; WorkflowRunId='d1' }
            [PSCustomObject]@{ Id='doc-2'; Name='docs'; SizeBytes=5000000; CreatedAt=[datetime]'2026-06-20'; WorkflowName='Docs'; WorkflowRunId='d2' }
            [PSCustomObject]@{ Id='doc-3'; Name='docs'; SizeBytes=5000000; CreatedAt=[datetime]'2026-06-01'; WorkflowName='Docs'; WorkflowRunId='d3' }
        )

        $plan = New-RetentionPlan -Artifacts $artifacts -MaxAgeDays 365 -MaxTotalSizeBytes 1000000000 -KeepLatestN 5 -Now ([datetime]'2026-07-01')

        $plan.RetainedCount | Should -Be 3
        $plan.DeletedCount | Should -Be 0
        $plan.ReclaimedBytes | Should -Be 0
    }

    It 'throws a meaningful error when artifact Ids are not unique' {
        $artifacts = @(
            [PSCustomObject]@{ Id='dup'; Name='a'; SizeBytes=1; CreatedAt=[datetime]'2026-06-01'; WorkflowName='CI'; WorkflowRunId='r1' }
            [PSCustomObject]@{ Id='dup'; Name='b'; SizeBytes=1; CreatedAt=[datetime]'2026-06-02'; WorkflowName='CI'; WorkflowRunId='r2' }
        )

        { New-RetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -MaxTotalSizeBytes 100 -KeepLatestN 1 -Now ([datetime]'2026-07-01') } |
            Should -Throw '*duplicate*Id*dup*'
    }

    It 'throws a meaningful error when MaxAgeDays is negative' {
        { New-RetentionPlan -Artifacts @() -MaxAgeDays -1 -MaxTotalSizeBytes 100 -KeepLatestN 1 -Now ([datetime]'2026-07-01') } |
            Should -Throw '*MaxAgeDays*'
    }

    It 'throws a meaningful error when KeepLatestN is negative' {
        { New-RetentionPlan -Artifacts @() -MaxAgeDays 30 -MaxTotalSizeBytes 100 -KeepLatestN -1 -Now ([datetime]'2026-07-01') } |
            Should -Throw '*KeepLatestN*'
    }

    It 'throws a meaningful error when MaxTotalSizeBytes is negative' {
        { New-RetentionPlan -Artifacts @() -MaxAgeDays 30 -MaxTotalSizeBytes -1 -KeepLatestN 1 -Now ([datetime]'2026-07-01') } |
            Should -Throw '*MaxTotalSizeBytes*'
    }
}

Describe 'Invoke-ArtifactCleanup' {

    BeforeAll {
        $script:samplePlan = New-RetentionPlan -Artifacts @(
            [PSCustomObject]@{ Id='keep'; Name='a'; SizeBytes=10; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='drop'; Name='a'; SizeBytes=10; CreatedAt=[datetime]'2026-01-01'; WorkflowName='CI'; WorkflowRunId='r1' }
        ) -MaxAgeDays 30 -MaxTotalSizeBytes 1000 -KeepLatestN 1 -Now ([datetime]'2026-07-01')
    }

    It 'invokes the delete action once per deleted artifact when not a dry run' {
        $deletedIds = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-ArtifactCleanup -Plan $script:samplePlan -DeleteAction { param($artifact) $deletedIds.Add($artifact.Id) }

        $deletedIds.Count | Should -Be 1
        $deletedIds | Should -Contain 'drop'
        $result.DryRun | Should -Be $false
        $result.ActionsInvoked | Should -Be 1
    }

    It 'never invokes the delete action in dry-run mode' {
        $deletedIds = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-ArtifactCleanup -Plan $script:samplePlan -DryRun -DeleteAction { param($artifact) $deletedIds.Add($artifact.Id) }

        $deletedIds.Count | Should -Be 0
        $result.DryRun | Should -Be $true
        $result.ActionsInvoked | Should -Be 0
    }
}

Describe 'Format-RetentionSummary' {

    BeforeAll {
        $script:samplePlan = New-RetentionPlan -Artifacts @(
            [PSCustomObject]@{ Id='keep'; Name='a'; SizeBytes=10000000; CreatedAt=[datetime]'2026-06-30'; WorkflowName='CI'; WorkflowRunId='r2' }
            [PSCustomObject]@{ Id='drop'; Name='a'; SizeBytes=20000000; CreatedAt=[datetime]'2026-01-01'; WorkflowName='CI'; WorkflowRunId='r1' }
        ) -MaxAgeDays 30 -MaxTotalSizeBytes 1000000000 -KeepLatestN 1 -Now ([datetime]'2026-07-01')
    }

    It 'reports exact retained/deleted counts and reclaimed size' {
        $summary = Format-RetentionSummary -Plan $script:samplePlan -DryRun:$false

        $summary | Should -Match 'Total artifacts scanned: 2'
        $summary | Should -Match 'Artifacts retained: 1'
        $summary | Should -Match 'Artifacts deleted: 1'
        $summary | Should -Match 'Total space reclaimed: 20000000 bytes \(20\.00 MB\)'
        $summary | Should -Not -Match 'DRY RUN'
    }

    It 'labels the report as a dry run when requested' {
        $summary = Format-RetentionSummary -Plan $script:samplePlan -DryRun:$true

        $summary | Should -Match 'DRY RUN'
        $summary | Should -Match 'Artifacts deleted: 1'
    }
}
