# Pester tests for the artifact cleanup logic.
# We follow red/green TDD: each Describe block was written as a failing test
# first, then the minimum code was added to ArtifactCleanup.psm1 to make it pass.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the directory of this file.
    Import-Module (Join-Path $PSScriptRoot 'ArtifactCleanup.psm1') -Force
}

Describe 'New-Artifact (test helper / fixture factory)' {
    It 'creates an artifact object with the expected properties' {
        $a = New-Artifact -Name 'build.zip' -SizeBytes 1000 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 101
        $a.Name          | Should -Be 'build.zip'
        $a.SizeBytes     | Should -Be 1000
        $a.WorkflowName  | Should -Be 'ci'
        $a.WorkflowRunId | Should -Be 101
        # CreatedAt should be normalised to a DateTime for safe comparison.
        $a.CreatedAt     | Should -BeOfType [datetime]
    }
}

Describe 'Get-ArtifactDeletionPlan - MaxAgeDays policy' {
    BeforeAll {
        $script:Now = [datetime]::Parse('2026-06-27T00:00:00Z', $null, 'AdjustToUniversal,AssumeUniversal')
        $script:Artifacts = @(
            New-Artifact -Name 'old.zip'    -SizeBytes 100 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 1  # 26 days old
            New-Artifact -Name 'recent.zip' -SizeBytes 200 -CreatedAt '2026-06-25T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 2  # 2 days old
        )
    }

    It 'marks artifacts older than MaxAgeDays for deletion' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now
        $plan.Delete.Name | Should -Be @('old.zip')
        $plan.Retain.Name | Should -Be @('recent.zip')
    }

    It 'attaches a human-readable reason for each deletion' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now
        $plan.Delete[0].Reason | Should -Match 'age'
    }

    It 'retains everything when no policy is supplied' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -Now $script:Now
        $plan.Delete.Count | Should -Be 0
        $plan.Retain.Count | Should -Be 2
    }
}

Describe 'Get-ArtifactDeletionPlan - KeepLatestN per workflow' {
    BeforeAll {
        $script:Now = [datetime]::Parse('2026-06-27T00:00:00Z', $null, 'AdjustToUniversal,AssumeUniversal')
        # Two workflows. 'ci' has 3 artifacts, 'nightly' has 2.
        $script:Artifacts = @(
            New-Artifact -Name 'ci-1.zip'      -SizeBytes 10 -CreatedAt '2026-06-20T00:00:00Z' -WorkflowName 'ci'      -WorkflowRunId 1
            New-Artifact -Name 'ci-2.zip'      -SizeBytes 10 -CreatedAt '2026-06-21T00:00:00Z' -WorkflowName 'ci'      -WorkflowRunId 2
            New-Artifact -Name 'ci-3.zip'      -SizeBytes 10 -CreatedAt '2026-06-22T00:00:00Z' -WorkflowName 'ci'      -WorkflowRunId 3
            New-Artifact -Name 'nightly-1.zip' -SizeBytes 10 -CreatedAt '2026-06-20T00:00:00Z' -WorkflowName 'nightly' -WorkflowRunId 4
            New-Artifact -Name 'nightly-2.zip' -SizeBytes 10 -CreatedAt '2026-06-21T00:00:00Z' -WorkflowName 'nightly' -WorkflowRunId 5
        )
    }

    It 'keeps only the N newest artifacts within each workflow group' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -KeepLatestN 1 -Now $script:Now
        ($plan.Retain.Name | Sort-Object) | Should -Be @('ci-3.zip', 'nightly-2.zip')
        ($plan.Delete.Name | Sort-Object) | Should -Be @('ci-1.zip', 'ci-2.zip', 'nightly-1.zip')
    }

    It 'keeps everything when a group has fewer than N artifacts' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -KeepLatestN 5 -Now $script:Now
        $plan.Delete.Count | Should -Be 0
    }

    It 'records a keep-latest reason on deleted artifacts' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -KeepLatestN 1 -Now $script:Now
        $plan.Delete[0].Reason | Should -Match 'keep'
    }
}

Describe 'Get-ArtifactDeletionPlan - MaxTotalSizeBytes policy' {
    BeforeAll {
        $script:Now = [datetime]::Parse('2026-06-27T00:00:00Z', $null, 'AdjustToUniversal,AssumeUniversal')
        # Total = 600 bytes. Oldest first: a(100) b(200) c(300).
        $script:Artifacts = @(
            New-Artifact -Name 'a.zip' -SizeBytes 100 -CreatedAt '2026-06-20T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 1
            New-Artifact -Name 'b.zip' -SizeBytes 200 -CreatedAt '2026-06-21T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 2
            New-Artifact -Name 'c.zip' -SizeBytes 300 -CreatedAt '2026-06-22T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 3
        )
    }

    It 'deletes oldest artifacts until total retained size is within the cap' {
        # Cap = 350. Retaining all = 600 (over). Delete a(100) -> 500 (over).
        # Delete b(200) -> 300 (under). So a and b go, c stays.
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxTotalSizeBytes 350 -Now $script:Now
        ($plan.Delete.Name | Sort-Object) | Should -Be @('a.zip', 'b.zip')
        $plan.Retain.Name | Should -Be @('c.zip')
    }

    It 'deletes nothing when total is already within the cap' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxTotalSizeBytes 1000 -Now $script:Now
        $plan.Delete.Count | Should -Be 0
    }

    It 'records a size reason on deleted artifacts' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxTotalSizeBytes 350 -Now $script:Now
        $plan.Delete[0].Reason | Should -Match 'size'
    }
}

Describe 'Get-ArtifactSummary' {
    BeforeAll {
        $script:Now = [datetime]::Parse('2026-06-27T00:00:00Z', $null, 'AdjustToUniversal,AssumeUniversal')
        $script:Artifacts = @(
            New-Artifact -Name 'old.zip'    -SizeBytes 500 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 1
            New-Artifact -Name 'recent.zip' -SizeBytes 200 -CreatedAt '2026-06-25T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 2
        )
    }

    It 'summarises counts and reclaimed space' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now
        $summary = Get-ArtifactSummary -Plan $plan
        $summary.DeletedCount         | Should -Be 1
        $summary.RetainedCount        | Should -Be 1
        $summary.TotalArtifacts       | Should -Be 2
        $summary.SpaceReclaimedBytes  | Should -Be 500
        $summary.SpaceRetainedBytes   | Should -Be 200
    }
}

Describe 'ConvertTo-Artifact (JSON loading)' {
    It 'converts raw PSObjects (e.g. from ConvertFrom-Json) into normalised artifacts' {
        $raw = '[{"name":"x.zip","sizeBytes":42,"createdAt":"2026-06-01T00:00:00Z","workflowName":"ci","workflowRunId":7}]' |
            ConvertFrom-Json
        $artifacts = ConvertTo-Artifact -InputObject $raw
        $artifacts.Count          | Should -Be 1
        $artifacts[0].Name        | Should -Be 'x.zip'
        $artifacts[0].SizeBytes   | Should -Be 42
        $artifacts[0].CreatedAt   | Should -BeOfType [datetime]
    }

    It 'throws a meaningful error when a required field is missing' {
        $raw = '[{"name":"x.zip"}]' | ConvertFrom-Json
        { ConvertTo-Artifact -InputObject $raw } | Should -Throw '*sizeBytes*'
    }
}

Describe 'Invoke-ArtifactCleanup - orchestration and dry-run' {
    BeforeAll {
        $script:Now = [datetime]::Parse('2026-06-27T00:00:00Z', $null, 'AdjustToUniversal,AssumeUniversal')
        $script:Artifacts = @(
            New-Artifact -Name 'old.zip'    -SizeBytes 500 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 1
            New-Artifact -Name 'recent.zip' -SizeBytes 200 -CreatedAt '2026-06-25T00:00:00Z' -WorkflowName 'ci' -WorkflowRunId 2
        )
    }

    It 'returns plan + summary together' {
        $r = Invoke-ArtifactCleanup -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now -DryRun
        $r.Summary.DeletedCount | Should -Be 1
        $r.Plan.Delete.Name     | Should -Be @('old.zip')
    }

    It 'does NOT invoke the deletion callback in dry-run mode' {
        $script:called = @()
        Invoke-ArtifactCleanup -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now -DryRun `
            -OnDelete { param($a) $script:called += $a.Name } | Out-Null
        $script:called.Count | Should -Be 0
    }

    It 'invokes the deletion callback once per deleted artifact when NOT dry-run' {
        $script:called = @()
        Invoke-ArtifactCleanup -Artifacts $script:Artifacts -MaxAgeDays 7 -Now $script:Now `
            -OnDelete { param($a) $script:called += $a.Name } | Out-Null
        $script:called | Should -Be @('old.zip')
    }

    It 'flags the result with the DryRun mode' {
        (Invoke-ArtifactCleanup -Artifacts $script:Artifacts -Now $script:Now -DryRun).DryRun | Should -BeTrue
        (Invoke-ArtifactCleanup -Artifacts $script:Artifacts -Now $script:Now).DryRun         | Should -BeFalse
    }
}
