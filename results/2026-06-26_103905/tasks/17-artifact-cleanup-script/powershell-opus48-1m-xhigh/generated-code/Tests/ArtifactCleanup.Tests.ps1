# Pester unit tests for the ArtifactCleanup module.
#
# These tests are written FIRST (red/green TDD): each describes a behaviour
# before the implementation exists. The module under test lives one directory up.

BeforeAll {
    # Resolve the module relative to this test file so it works from any CWD
    # (local dev, CI container, act, etc.).
    $script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'ArtifactCleanup.psm1'
    Import-Module $script:ModulePath -Force

    # Small helper so individual tests can build artifact records tersely.
    function New-TestArtifact {
        param(
            [string]$Name,
            [long]$SizeBytes,
            [datetime]$Created,
            [string]$WorkflowRunId
        )
        New-ArtifactRecord -Name $Name -SizeBytes $SizeBytes -Created $Created -WorkflowRunId $WorkflowRunId
    }

    # A fixed reference "now" makes every age-based assertion deterministic.
    $script:Now = [datetime]'2026-06-28T00:00:00Z'
}

Describe 'Get-ArtifactCleanupPlan - no policies' {
    It 'retains every artifact and reclaims nothing when no policy is supplied' {
        $artifacts = @(
            New-TestArtifact -Name 'build' -SizeBytes 100 -Created $script:Now.AddDays(-1) -WorkflowRunId '1'
            New-TestArtifact -Name 'test'  -SizeBytes 200 -Created $script:Now.AddDays(-2) -WorkflowRunId '2'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -Now $script:Now

        $plan.Summary.TotalArtifacts | Should -Be 2
        $plan.Summary.RetainedCount  | Should -Be 2
        $plan.Summary.DeletedCount   | Should -Be 0
        $plan.Summary.ReclaimedBytes | Should -Be 0
        @($plan.Deleted).Count       | Should -Be 0
    }
}

Describe 'Get-ArtifactCleanupPlan - max age policy' {
    It 'deletes artifacts older than the max age and keeps the rest' {
        $artifacts = @(
            New-TestArtifact -Name 'fresh' -SizeBytes 100 -Created $script:Now.AddDays(-5)  -WorkflowRunId '1'
            New-TestArtifact -Name 'stale' -SizeBytes 400 -Created $script:Now.AddDays(-40) -WorkflowRunId '2'
            New-TestArtifact -Name 'edge'  -SizeBytes 50  -Created $script:Now.AddDays(-30) -WorkflowRunId '3'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

        # Only 'stale' (40 days) is strictly older than 30 days; 'edge' at exactly
        # 30 days is on the boundary and must be kept.
        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.RetainedCount  | Should -Be 2
        $plan.Summary.ReclaimedBytes | Should -Be 400
        $plan.Deleted[0].Name        | Should -Be 'stale'
        $plan.Deleted[0].Reasons     | Should -Contain 'Exceeds max age (30 days)'
    }
}

Describe 'Get-ArtifactCleanupPlan - keep latest N per workflow' {
    # "Per workflow" groups by artifact Name: in GitHub Actions the same workflow
    # re-uploads an artifact under the same name on every run, so each Name is one
    # workflow's artifact "stream" and WorkflowRunId distinguishes the runs.
    It 'keeps only the N most recent runs of each named artifact' {
        $artifacts = @(
            New-TestArtifact -Name 'build' -SizeBytes 10 -Created $script:Now.AddDays(-1) -WorkflowRunId '101'
            New-TestArtifact -Name 'build' -SizeBytes 20 -Created $script:Now.AddDays(-2) -WorkflowRunId '102'
            New-TestArtifact -Name 'build' -SizeBytes 40 -Created $script:Now.AddDays(-3) -WorkflowRunId '103'
            New-TestArtifact -Name 'test'  -SizeBytes 5  -Created $script:Now.AddDays(-1) -WorkflowRunId '201'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 2 -Now $script:Now

        # 'build' has 3 runs -> keep the 2 newest (101, 102), delete the oldest (103).
        # 'test' has only 1 run -> kept.
        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.RetainedCount  | Should -Be 3
        $plan.Summary.ReclaimedBytes | Should -Be 40
        $plan.Deleted[0].WorkflowRunId | Should -Be '103'
        $plan.Deleted[0].Reasons | Should -Contain 'Exceeds keep-latest-N per workflow (keep 2)'
    }

    It 'breaks ties on creation date using the workflow run id (higher = newer)' {
        $sameTime = $script:Now.AddDays(-1)
        $artifacts = @(
            New-TestArtifact -Name 'pkg' -SizeBytes 1 -Created $sameTime -WorkflowRunId '500'
            New-TestArtifact -Name 'pkg' -SizeBytes 2 -Created $sameTime -WorkflowRunId '700'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 1 -Now $script:Now

        $plan.Summary.DeletedCount     | Should -Be 1
        $plan.Deleted[0].WorkflowRunId | Should -Be '500'   # lower run id is the older one
    }
}

Describe 'Get-ArtifactCleanupPlan - max total size policy' {
    It 'evicts the oldest artifacts until the retained total fits the budget' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -SizeBytes 100 -Created $script:Now.AddDays(-1) -WorkflowRunId '1'
            New-TestArtifact -Name 'b' -SizeBytes 100 -Created $script:Now.AddDays(-2) -WorkflowRunId '2'
            New-TestArtifact -Name 'c' -SizeBytes 100 -Created $script:Now.AddDays(-3) -WorkflowRunId '3'
            New-TestArtifact -Name 'd' -SizeBytes 100 -Created $script:Now.AddDays(-4) -WorkflowRunId '4'
        )

        # Budget 250 -> must drop the two oldest (d then c) to get to 200 <= 250.
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 250 -Now $script:Now

        $plan.Summary.DeletedCount      | Should -Be 2
        $plan.Summary.RetainedSizeBytes | Should -Be 200
        $plan.Summary.ReclaimedBytes    | Should -Be 200
        ($plan.Deleted.Name | Sort-Object) | Should -Be @('c', 'd')
        $plan.Deleted[0].Reasons | Should -Contain 'Exceeds max total size (250 bytes)'
    }

    It 'does nothing when the retained total already fits the budget' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -SizeBytes 100 -Created $script:Now.AddDays(-1) -WorkflowRunId '1'
            New-TestArtifact -Name 'b' -SizeBytes 100 -Created $script:Now.AddDays(-2) -WorkflowRunId '2'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 1000 -Now $script:Now

        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Get-ArtifactCleanupPlan - combined policies' {
    It 'records every applicable reason when an artifact violates several policies' {
        $artifacts = @(
            New-TestArtifact -Name 'build' -SizeBytes 10 -Created $script:Now.AddDays(-1)  -WorkflowRunId '103'
            New-TestArtifact -Name 'build' -SizeBytes 10 -Created $script:Now.AddDays(-2)  -WorkflowRunId '102'
            # Old AND the surplus (3rd) run of 'build' -> two reasons.
            New-TestArtifact -Name 'build' -SizeBytes 10 -Created $script:Now.AddDays(-99) -WorkflowRunId '101'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 2 -Now $script:Now

        $plan.Summary.DeletedCount | Should -Be 1
        $old = $plan.Deleted | Where-Object WorkflowRunId -eq '101'
        $old.Reasons | Should -Contain 'Exceeds max age (30 days)'
        $old.Reasons | Should -Contain 'Exceeds keep-latest-N per workflow (keep 2)'
        @($old.Reasons).Count | Should -Be 2
    }

    It 'applies age, keep-N and size policies together' {
        $artifacts = @(
            New-TestArtifact -Name 'big'   -SizeBytes 500 -Created $script:Now.AddDays(-1)  -WorkflowRunId '1'
            New-TestArtifact -Name 'big'   -SizeBytes 500 -Created $script:Now.AddDays(-2)  -WorkflowRunId '2'
            New-TestArtifact -Name 'big'   -SizeBytes 500 -Created $script:Now.AddDays(-3)  -WorkflowRunId '3'
            New-TestArtifact -Name 'small' -SizeBytes 10  -Created $script:Now.AddDays(-90) -WorkflowRunId '4'
        )

        # age 30 -> drops 'small'(90d). keep 2 of 'big' -> drops run 3.
        # remaining big runs 1+2 = 1000 bytes, budget 600 -> evict oldest (run 2).
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 2 -MaxTotalSizeBytes 600 -Now $script:Now

        $plan.Summary.DeletedCount      | Should -Be 3
        $plan.Summary.RetainedCount     | Should -Be 1
        $plan.Summary.RetainedSizeBytes | Should -Be 500
        ($plan.Retained[0].WorkflowRunId) | Should -Be '1'
    }
}

Describe 'Format-FileSize' {
    It 'renders <Bytes> bytes as <Expected>' -ForEach @(
        @{ Bytes = 0L;          Expected = '0 B' }
        @{ Bytes = 512L;        Expected = '512 B' }
        @{ Bytes = 1023L;       Expected = '1023 B' }
        @{ Bytes = 1024L;       Expected = '1 KB' }
        @{ Bytes = 1536L;       Expected = '1.5 KB' }
        @{ Bytes = 1048576L;    Expected = '1 MB' }
        @{ Bytes = 1610612736L; Expected = '1.5 GB' }
    ) {
        Format-FileSize -Bytes $Bytes | Should -Be $Expected
    }
}

Describe 'Get-ArtifactCleanupPlan - summary enrichment' {
    It 'exposes human-readable sizes and echoes the policies applied' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -SizeBytes 1048576 -Created $script:Now.AddDays(-40) -WorkflowRunId '1'
            New-TestArtifact -Name 'b' -SizeBytes 1048576 -Created $script:Now.AddDays(-1)  -WorkflowRunId '2'
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

        $plan.Summary.ReclaimedHuman    | Should -Be '1 MB'
        $plan.Summary.TotalSizeHuman    | Should -Be '2 MB'
        $plan.Summary.RetainedSizeHuman | Should -Be '1 MB'
        $plan.Policies.MaxAgeDays            | Should -Be 30
        $plan.Policies.KeepLatestPerWorkflow | Should -Be 0
        $plan.Policies.MaxTotalSizeBytes     | Should -Be 0
    }
}

Describe 'Format-ArtifactCleanupPlan' {
    BeforeAll {
        $artifacts = @(
            New-TestArtifact -Name 'old-build' -SizeBytes 1048576 -Created $script:Now.AddDays(-40) -WorkflowRunId '111'
            New-TestArtifact -Name 'new-build' -SizeBytes 1048576 -Created $script:Now.AddDays(-1)  -WorkflowRunId '222'
        )
        $script:plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now
    }

    It 'renders the summary counts and reclaimed space' {
        $report = (Format-ArtifactCleanupPlan -Plan $script:plan) -join "`n"

        $report | Should -Match 'Artifacts:\s+2 total'
        $report | Should -Match 'To delete:\s+1'
        $report | Should -Match 'To retain:\s+1'
        $report | Should -Match 'Space reclaimed:\s+1 MB'
    }

    It 'lists each artifact slated for deletion with its reason' {
        $report = (Format-ArtifactCleanupPlan -Plan $script:plan) -join "`n"

        $report | Should -Match 'old-build'
        $report | Should -Match 'Exceeds max age \(30 days\)'
    }

    It 'shows a DRY RUN banner only when -DryRun is passed' {
        $dry  = (Format-ArtifactCleanupPlan -Plan $script:plan -DryRun) -join "`n"
        $real = (Format-ArtifactCleanupPlan -Plan $script:plan) -join "`n"

        $dry  | Should -Match 'DRY RUN'
        $real | Should -Not -Match 'DRY RUN'
    }
}

Describe 'Invoke-ArtifactCleanup - fixture loading and dry-run' {
    BeforeAll {
        # Write a self-contained fixture to Pester's TestDrive.
        $script:fixture = Join-Path $TestDrive 'sample.json'
        @{
            referenceDate = '2026-06-28T00:00:00Z'
            policies      = @{ maxAgeDays = 30; keepLatestPerWorkflow = 0; maxTotalSizeBytes = 0 }
            artifacts     = @(
                @{ name = 'keep'; sizeBytes = 100; created = '2026-06-27T00:00:00Z'; workflowRunId = '1' }
                @{ name = 'drop'; sizeBytes = 300; created = '2026-01-01T00:00:00Z'; workflowRunId = '2' }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:fixture
    }

    It 'loads artifacts and policies from a JSON file and builds the plan' {
        $result = Invoke-ArtifactCleanup -Path $script:fixture -DryRun

        $result.Plan.Summary.TotalArtifacts | Should -Be 2
        $result.Plan.Summary.DeletedCount   | Should -Be 1
        $result.Plan.Summary.ReclaimedBytes | Should -Be 300
        $result.Plan.Deleted[0].Name        | Should -Be 'drop'
    }

    It 'does NOT invoke the delete action in dry-run mode' {
        $script:called = 0
        $action = { param($artifact) $script:called++ }

        $result = Invoke-ArtifactCleanup -Path $script:fixture -DryRun -DeleteAction $action

        $result.DryRun           | Should -BeTrue
        $result.DeletedPerformed | Should -Be 0
        $script:called           | Should -Be 0
    }

    It 'invokes the delete action once per deleted artifact when not a dry run' {
        $script:called = 0
        $action = { param($artifact) $script:called++ }

        $result = Invoke-ArtifactCleanup -Path $script:fixture -DeleteAction $action

        $result.DryRun           | Should -BeFalse
        $result.DeletedPerformed | Should -Be 1
        $script:called           | Should -Be 1
    }

    It 'exposes machine-readable metric lines for downstream parsing' {
        $result = Invoke-ArtifactCleanup -Path $script:fixture -DryRun
        $metrics = $result.MetricLines -join "`n"

        $metrics | Should -Match 'ARTIFACTS_TOTAL=2'
        $metrics | Should -Match 'ARTIFACTS_DELETED=1'
        $metrics | Should -Match 'ARTIFACTS_RETAINED=1'
        $metrics | Should -Match 'SPACE_RECLAIMED_BYTES=300'
        $metrics | Should -Match 'DRY_RUN=true'
    }
}

Describe 'Invoke-ArtifactCleanup - error handling' {
    It 'throws a meaningful error when the fixture file is missing' {
        { Invoke-ArtifactCleanup -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error when the JSON is invalid' {
        $bad = Join-Path $TestDrive 'bad.json'
        'this is { not json' | Set-Content -Path $bad
        { Invoke-ArtifactCleanup -Path $bad } | Should -Throw '*Failed to parse*'
    }

    It 'throws a meaningful error when an artifact is missing required fields' {
        $bad = Join-Path $TestDrive 'missing.json'
        @{ artifacts = @(@{ name = 'x' }) } | ConvertTo-Json -Depth 5 | Set-Content -Path $bad
        { Invoke-ArtifactCleanup -Path $bad } | Should -Throw '*missing required field*'
    }
}

Describe 'Get-ArtifactCleanupPlan - edge cases' {
    It 'handles an empty artifact list without error' {
        $plan = Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays 30 -Now $script:Now

        $plan.Summary.TotalArtifacts | Should -Be 0
        $plan.Summary.ReclaimedBytes | Should -Be 0
        @($plan.Deleted).Count       | Should -Be 0
    }
}
