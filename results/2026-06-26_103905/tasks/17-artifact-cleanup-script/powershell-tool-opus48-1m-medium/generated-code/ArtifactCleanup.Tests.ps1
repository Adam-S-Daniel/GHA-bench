# ArtifactCleanup.Tests.ps1
# Pester tests for the artifact retention / cleanup engine.
# Written red/green TDD style: each Describe block was added as a failing
# test before the corresponding code in ArtifactCleanup.psm1 existed.

BeforeAll {
    # Import the module under test. Remove first so repeated runs pick up edits.
    $modulePath = Join-Path $PSScriptRoot 'ArtifactCleanup.psm1'
    Remove-Module ArtifactCleanup -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force

    # Helper to build an artifact object with sensible defaults.
    function New-TestArtifact {
        param(
            [string]   $Name,
            [long]     $Size,
            [datetime] $CreationDate,
            [string]   $WorkflowRunId = 'run-1'
        )
        [pscustomobject]@{
            Name          = $Name
            Size          = $Size
            CreationDate  = $CreationDate
            WorkflowRunId = $WorkflowRunId
        }
    }

    # A fixed "now" so age-based tests are deterministic.
    $script:Now = [datetime]'2026-06-26T00:00:00Z'
}

Describe 'New-ArtifactCleanupPlan - basics' {
    It 'retains everything when no policies are set' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -Size 100 -CreationDate $script:Now.AddDays(-1)
            New-TestArtifact -Name 'b' -Size 200 -CreationDate $script:Now.AddDays(-2)
        )
        $plan = New-ArtifactCleanupPlan -Artifacts $artifacts -Now $script:Now

        $plan.Summary.TotalArtifacts | Should -Be 2
        $plan.Summary.RetainedCount  | Should -Be 2
        $plan.Summary.DeletedCount   | Should -Be 0
        $plan.Summary.SpaceReclaimed | Should -Be 0
    }

    It 'throws a meaningful error when an artifact is missing required fields' {
        $bad = @([pscustomobject]@{ Name = 'x'; Size = 10 })  # no CreationDate / WorkflowRunId
        { New-ArtifactCleanupPlan -Artifacts $bad -Now $script:Now } |
            Should -Throw -ExpectedMessage '*CreationDate*'
    }

    It 'throws on negative size' {
        $bad = @(New-TestArtifact -Name 'x' -Size -5 -CreationDate $script:Now)
        { New-ArtifactCleanupPlan -Artifacts $bad -Now $script:Now } |
            Should -Throw -ExpectedMessage '*negative*'
    }
}

Describe 'New-ArtifactCleanupPlan - max age policy' {
    It 'deletes artifacts older than MaxAgeDays' {
        $artifacts = @(
            New-TestArtifact -Name 'fresh' -Size 100 -CreationDate $script:Now.AddDays(-5)
            New-TestArtifact -Name 'stale' -Size 300 -CreationDate $script:Now.AddDays(-40)
        )
        $plan = New-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.SpaceReclaimed | Should -Be 300
        ($plan.Delete | Where-Object Name -eq 'stale').Reasons | Should -Contain 'MaxAge'
    }
}

Describe 'New-ArtifactCleanupPlan - keep latest N per workflow' {
    It 'keeps only the N newest artifacts per workflow run' {
        $artifacts = @(
            New-TestArtifact -Name 'r1-old'  -Size 10 -CreationDate $script:Now.AddDays(-3) -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r1-mid'  -Size 10 -CreationDate $script:Now.AddDays(-2) -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r1-new'  -Size 10 -CreationDate $script:Now.AddDays(-1) -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r2-only' -Size 10 -CreationDate $script:Now.AddDays(-1) -WorkflowRunId 'run-2'
        )
        $plan = New-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 2 -Now $script:Now

        # run-1 keeps the 2 newest (r1-new, r1-mid); r1-old deleted. run-2 untouched.
        $plan.Summary.DeletedCount | Should -Be 1
        ($plan.Delete | Where-Object Name -eq 'r1-old').Reasons | Should -Contain 'KeepLatest'
        $plan.Retain.Name | Should -Contain 'r2-only'
    }
}

Describe 'New-ArtifactCleanupPlan - max total size policy' {
    It 'deletes oldest artifacts until total size fits the budget' {
        $artifacts = @(
            New-TestArtifact -Name 'old'    -Size 500 -CreationDate $script:Now.AddDays(-3)
            New-TestArtifact -Name 'medium' -Size 500 -CreationDate $script:Now.AddDays(-2)
            New-TestArtifact -Name 'new'    -Size 500 -CreationDate $script:Now.AddDays(-1)
        )
        # Budget 1000 -> must drop the oldest (500) so 1000 remains.
        $plan = New-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSize 1000 -Now $script:Now

        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.SpaceReclaimed | Should -Be 500
        ($plan.Delete | Where-Object Name -eq 'old').Reasons | Should -Contain 'MaxSize'
        # Retained total must be within budget.
        ($plan.Retain | Measure-Object Size -Sum).Sum | Should -BeLessOrEqual 1000
    }
}

Describe 'New-ArtifactCleanupPlan - combined policies' {
    It 'applies age, keep-latest and size together with one reason set per artifact' {
        $artifacts = @(
            New-TestArtifact -Name 'ancient' -Size 100 -CreationDate $script:Now.AddDays(-100) -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r1-a'    -Size 700 -CreationDate $script:Now.AddDays(-3)   -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r1-b'    -Size 700 -CreationDate $script:Now.AddDays(-2)   -WorkflowRunId 'run-1'
            New-TestArtifact -Name 'r1-c'    -Size 700 -CreationDate $script:Now.AddDays(-1)   -WorkflowRunId 'run-1'
        )
        $plan = New-ArtifactCleanupPlan -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 2 -MaxTotalSize 1000 -Now $script:Now

        # ancient -> MaxAge. r1-a -> KeepLatest (only 2 newest kept). Of remaining
        # r1-b/r1-c (1400 bytes) one more must go for the 1000 budget: oldest = r1-b.
        ($plan.Delete | Where-Object Name -eq 'ancient').Reasons | Should -Contain 'MaxAge'
        ($plan.Delete | Where-Object Name -eq 'r1-a').Reasons    | Should -Contain 'KeepLatest'
        $plan.Retain.Name | Should -Be @('r1-c')
        ($plan.Retain | Measure-Object Size -Sum).Sum | Should -BeLessOrEqual 1000
    }
}

Describe 'Format-CleanupReport - human readable output' {
    It 'emits a stable summary block usable by CI assertions' {
        $artifacts = @(
            New-TestArtifact -Name 'keep' -Size 100 -CreationDate $script:Now.AddDays(-1)
            New-TestArtifact -Name 'drop' -Size 250 -CreationDate $script:Now.AddDays(-99)
        )
        $plan   = New-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now
        $report = Format-CleanupReport -Plan $plan -DryRun

        $report | Should -Match 'PLAN_SUMMARY_BEGIN'
        $report | Should -Match 'TotalArtifacts: 2'
        $report | Should -Match 'Deleted: 1'
        $report | Should -Match 'SpaceReclaimed: 250'
        $report | Should -Match 'DryRun: True'
        $report | Should -Match 'PLAN_SUMMARY_END'
    }
}
