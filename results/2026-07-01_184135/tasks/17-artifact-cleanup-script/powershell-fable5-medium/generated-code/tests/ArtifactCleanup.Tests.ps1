# Pester tests for the artifact cleanup planner.
# Built with red/green TDD: each Context below was written as a failing test
# first, then the minimum implementation was added to src/ArtifactCleanup.psm1.

BeforeAll {
    # Import the module fresh each run so edits are picked up.
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force

    # Fixed "now" so age calculations are deterministic in tests and CI.
    $script:RefDate = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()

    # Helper to build mock artifact records (our test fixture factory).
    function New-MockArtifact {
        param(
            [string]$Name,
            [long]$SizeBytes,
            [string]$CreatedAt,
            [string]$WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
        }
    }
}

Describe 'Get-ArtifactCleanupPlan' {

    Context 'max age policy' {
        It 'deletes artifacts older than MaxAgeDays and retains newer ones' {
            $artifacts = @(
                New-MockArtifact -Name 'old-build'  -SizeBytes 100 -CreatedAt '2026-05-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'new-build'  -SizeBytes 200 -CreatedAt '2026-06-29T00:00:00Z' -WorkflowRunId 'wf-1'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

            $plan.Deleted.Name  | Should -Be @('old-build')
            $plan.Retained.Name | Should -Be @('new-build')
            $plan.Deleted[0].Reason | Should -Be 'MaxAge'
        }

        It 'retains everything when no policy is supplied' {
            $artifacts = @(
                New-MockArtifact -Name 'a' -SizeBytes 1 -CreatedAt '2020-01-01T00:00:00Z' -WorkflowRunId 'wf-1'
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -ReferenceDate $script:RefDate
            $plan.Deleted  | Should -BeNullOrEmpty
            $plan.Retained.Name | Should -Be @('a')
        }
    }

    Context 'keep-latest-N per workflow policy' {
        It 'protects the newest N artifacts per workflow run from the age rule' {
            # All three are older than 30 days, but the newest 2 of wf-1 are protected.
            $artifacts = @(
                New-MockArtifact -Name 'wf1-oldest' -SizeBytes 10 -CreatedAt '2026-03-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'wf1-middle' -SizeBytes 10 -CreatedAt '2026-04-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'wf1-newest' -SizeBytes 10 -CreatedAt '2026-05-01T00:00:00Z' -WorkflowRunId 'wf-1'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 `
                -KeepLatestPerWorkflow 2 -ReferenceDate $script:RefDate

            $plan.Deleted.Name | Should -Be @('wf1-oldest')
            ($plan.Retained.Name | Sort-Object) | Should -Be @('wf1-middle', 'wf1-newest')
        }

        It 'applies the protection independently for each workflow run id' {
            $artifacts = @(
                New-MockArtifact -Name 'wf1-old' -SizeBytes 10 -CreatedAt '2026-01-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'wf1-new' -SizeBytes 10 -CreatedAt '2026-02-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'wf2-old' -SizeBytes 10 -CreatedAt '2026-01-01T00:00:00Z' -WorkflowRunId 'wf-2'
                New-MockArtifact -Name 'wf2-new' -SizeBytes 10 -CreatedAt '2026-02-01T00:00:00Z' -WorkflowRunId 'wf-2'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 `
                -KeepLatestPerWorkflow 1 -ReferenceDate $script:RefDate

            ($plan.Deleted.Name | Sort-Object)  | Should -Be @('wf1-old', 'wf2-old')
            ($plan.Retained.Name | Sort-Object) | Should -Be @('wf1-new', 'wf2-new')
        }
    }

    Context 'max total size policy' {
        It 'deletes oldest unprotected artifacts until total retained size fits the budget' {
            $artifacts = @(
                New-MockArtifact -Name 'oldest' -SizeBytes 400 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'middle' -SizeBytes 300 -CreatedAt '2026-06-10T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'newest' -SizeBytes 200 -CreatedAt '2026-06-20T00:00:00Z' -WorkflowRunId 'wf-1'
            )

            # Total is 900; budget 500 forces deleting 'oldest' (400) -> 500 fits.
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 500 -ReferenceDate $script:RefDate

            $plan.Deleted.Name  | Should -Be @('oldest')
            $plan.Deleted[0].Reason | Should -Be 'MaxTotalSize'
            ($plan.Retained.Name | Sort-Object) | Should -Be @('middle', 'newest')
        }

        It 'never evicts artifacts protected by keep-latest-N, even over budget' {
            $artifacts = @(
                New-MockArtifact -Name 'only' -SizeBytes 1000 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowRunId 'wf-1'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 500 `
                -KeepLatestPerWorkflow 1 -ReferenceDate $script:RefDate

            $plan.Deleted | Should -BeNullOrEmpty
            $plan.Retained.Name | Should -Be @('only')
        }
    }

    Context 'plan summary' {
        It 'reports totals, counts and space reclaimed' {
            $artifacts = @(
                New-MockArtifact -Name 'old-1' -SizeBytes 150 -CreatedAt '2026-01-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'old-2' -SizeBytes 250 -CreatedAt '2026-02-01T00:00:00Z' -WorkflowRunId 'wf-1'
                New-MockArtifact -Name 'fresh' -SizeBytes 600 -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 'wf-2'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

            $plan.Summary.TotalArtifacts      | Should -Be 3
            $plan.Summary.DeletedCount        | Should -Be 2
            $plan.Summary.RetainedCount       | Should -Be 1
            $plan.Summary.SpaceReclaimedBytes | Should -Be 400
            $plan.Summary.RetainedSizeBytes   | Should -Be 600
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when an artifact is missing a required field' {
            $bad = @([pscustomobject]@{ Name = 'no-date'; SizeBytes = 1; WorkflowRunId = 'wf-1' })
            { Get-ArtifactCleanupPlan -Artifacts $bad -ReferenceDate $script:RefDate } |
                Should -Throw "*'no-date'*CreatedAt*"
        }

        It 'throws a meaningful error for an unparseable creation date' {
            $bad = @(New-MockArtifact -Name 'bad-date' -SizeBytes 1 -CreatedAt 'not-a-date' -WorkflowRunId 'wf-1')
            { Get-ArtifactCleanupPlan -Artifacts $bad -ReferenceDate $script:RefDate } |
                Should -Throw "*'bad-date'*CreatedAt*not-a-date*"
        }

        It 'rejects negative policy values' {
            $ok = @(New-MockArtifact -Name 'a' -SizeBytes 1 -CreatedAt '2026-06-01T00:00:00Z' -WorkflowRunId 'wf-1')
            { Get-ArtifactCleanupPlan -Artifacts $ok -MaxAgeDays -5 -ReferenceDate $script:RefDate } |
                Should -Throw '*MaxAgeDays*'
        }

        It 'handles an empty artifact list gracefully' {
            $plan = Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays 30 -ReferenceDate $script:RefDate
            $plan.Summary.TotalArtifacts | Should -Be 0
            $plan.Summary.SpaceReclaimedBytes | Should -Be 0
        }
    }
}

Describe 'Invoke-ArtifactCleanup' {

    BeforeEach {
        $script:artifacts = @(
            New-MockArtifact -Name 'stale' -SizeBytes 100 -CreatedAt '2026-01-01T00:00:00Z' -WorkflowRunId 'wf-1'
            New-MockArtifact -Name 'fresh' -SizeBytes 200 -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 'wf-1'
        )
        $script:plan = Get-ArtifactCleanupPlan -Artifacts $script:artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate
    }

    It 'invokes the deleter for every planned deletion when not in dry-run' {
        # The deleter scriptblock is our mock for the real deletion API call.
        $deletedNames = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-ArtifactCleanup -Plan $script:plan -Deleter { param($a) $deletedNames.Add($a.Name) }.GetNewClosure()

        $deletedNames | Should -Be @('stale')
        $result.DryRun | Should -BeFalse
        $result.DeletedCount | Should -Be 1
    }

    It 'does NOT invoke the deleter in dry-run mode but still reports the plan' {
        $calls = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-ArtifactCleanup -Plan $script:plan -DryRun -Deleter { param($a) $calls.Add($a.Name) }.GetNewClosure()

        $calls.Count | Should -Be 0
        $result.DryRun | Should -BeTrue
        $result.DeletedCount | Should -Be 1
        $result.SpaceReclaimedBytes | Should -Be 100
    }

    It 'surfaces a meaningful error when the deleter fails' {
        { Invoke-ArtifactCleanup -Plan $script:plan -Deleter { throw 'API down' } } |
            Should -Throw "*Failed to delete artifact 'stale'*API down*"
    }
}
