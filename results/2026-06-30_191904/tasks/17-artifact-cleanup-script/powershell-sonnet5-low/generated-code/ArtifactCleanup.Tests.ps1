# Pester tests for ArtifactCleanup.psm1
# TDD: written before the corresponding implementation in ArtifactCleanup.psm1

BeforeAll {
    Import-Module "$PSScriptRoot/ArtifactCleanup.psm1" -Force
}

Describe 'Get-ArtifactCleanupPlan - Max Age policy' {
    It 'marks artifacts older than MaxAgeDays for deletion' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'old-artifact'; SizeBytes = 100; CreatedAt = $now.AddDays(-40); WorkflowRunId = 'run1' }
            [PSCustomObject]@{ Name = 'new-artifact'; SizeBytes = 100; CreatedAt = $now.AddDays(-5); WorkflowRunId = 'run2' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $now

        ($plan.ToDelete | Where-Object { $_.Name -eq 'old-artifact' }) | Should -Not -BeNullOrEmpty
        ($plan.ToRetain | Where-Object { $_.Name -eq 'new-artifact' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ArtifactCleanupPlan - Keep Latest N per workflow' {
    It 'keeps only the newest KeepLatestN artifacts for each workflow run group' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'wf1-a'; SizeBytes = 100; CreatedAt = $now.AddDays(-1); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'wf1-b'; SizeBytes = 100; CreatedAt = $now.AddDays(-2); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'wf1-c'; SizeBytes = 100; CreatedAt = $now.AddDays(-3); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'wf2-a'; SizeBytes = 100; CreatedAt = $now.AddDays(-1); WorkflowRunId = 'wf2' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 2 -Now $now

        $plan.ToDelete.Name | Should -Be @('wf1-c')
        ($plan.ToRetain.Name | Sort-Object) | Should -Be @('wf1-a', 'wf1-b', 'wf2-a')
    }
}

Describe 'Get-ArtifactCleanupPlan - Max Total Size policy' {
    It 'deletes oldest artifacts first until total retained size is under the cap' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'a'; SizeBytes = 100; CreatedAt = $now.AddDays(-1); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'b'; SizeBytes = 100; CreatedAt = $now.AddDays(-2); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'c'; SizeBytes = 100; CreatedAt = $now.AddDays(-3); WorkflowRunId = 'wf1' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 150 -Now $now

        ($plan.ToDelete.Name | Sort-Object) | Should -Be @('b', 'c')
        $plan.ToRetain.Name | Should -Be @('a')
    }
}

Describe 'Get-ArtifactCleanupPlan - Summary' {
    It 'computes total space reclaimed and retained/deleted counts' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'old'; SizeBytes = 500; CreatedAt = $now.AddDays(-40); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'new'; SizeBytes = 300; CreatedAt = $now.AddDays(-1); WorkflowRunId = 'wf1' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $now

        $plan.Summary.TotalSpaceReclaimedBytes | Should -Be 500
        $plan.Summary.RetainedCount | Should -Be 1
        $plan.Summary.DeletedCount | Should -Be 1
    }
}

Describe 'Invoke-ArtifactCleanup - Dry Run mode' {
    It 'does not call the delete action when DryRun is specified, but reports what would be deleted' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'old'; SizeBytes = 500; CreatedAt = $now.AddDays(-40); WorkflowRunId = 'wf1' }
        )
        $deletedNames = @()
        $deleteAction = { param($artifact) $script:deletedNames += $artifact.Name }

        $result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays 30 -Now $now -DryRun -DeleteAction $deleteAction

        $deletedNames | Should -BeNullOrEmpty
        $result.DryRun | Should -Be $true
        $result.Plan.ToDelete.Name | Should -Be @('old')
    }

    It 'invokes the delete action for each artifact to delete when not a dry run' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'old'; SizeBytes = 500; CreatedAt = $now.AddDays(-40); WorkflowRunId = 'wf1' }
        )
        $script:deletedNames = @()
        $deleteAction = { param($artifact) $script:deletedNames += $artifact.Name }

        $result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays 30 -Now $now -DeleteAction $deleteAction

        $script:deletedNames | Should -Be @('old')
        $result.DryRun | Should -Be $false
    }
}

Describe 'Get-ArtifactCleanupPlan - Error handling' {
    It 'throws a meaningful error when an artifact is missing required properties' {
        $badArtifact = [PSCustomObject]@{ Name = 'bad' }

        { Get-ArtifactCleanupPlan -Artifacts @($badArtifact) -MaxAgeDays 30 } | Should -Throw '*missing required property*'
    }

    It 'throws a meaningful error when MaxTotalSizeBytes is negative' {
        { Get-ArtifactCleanupPlan -Artifacts @() -MaxTotalSizeBytes -1 } | Should -Throw '*MaxTotalSizeBytes*'
    }
}

Describe 'Format-CleanupReport' {
    It 'renders a human-readable report including reclaimed space and counts' {
        $now = Get-Date '2026-07-01'
        $artifacts = @(
            [PSCustomObject]@{ Name = 'old'; SizeBytes = 500; CreatedAt = $now.AddDays(-40); WorkflowRunId = 'wf1' }
            [PSCustomObject]@{ Name = 'new'; SizeBytes = 300; CreatedAt = $now.AddDays(-1); WorkflowRunId = 'wf1' }
        )
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $now

        $report = Format-CleanupReport -Plan $plan -DryRun

        $report | Should -Match 'DRY RUN'
        $report | Should -Match 'Deleted:\s*1'
        $report | Should -Match 'Retained:\s*1'
        $report | Should -Match 'Space reclaimed:\s*500 bytes'
        $report | Should -Match 'old'
    }
}
