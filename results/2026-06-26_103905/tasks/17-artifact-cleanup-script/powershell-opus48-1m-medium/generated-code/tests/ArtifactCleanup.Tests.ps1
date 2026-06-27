#Requires -Modules Pester

<#
    Unit tests for the artifact retention engine.

    These tests were written FIRST (red), then the module was implemented to make
    them pass (green). Each retention policy is exercised in isolation so that a
    failure points at exactly one piece of behaviour.
#>

BeforeAll {
    # Import the module under test relative to this test file.
    $modulePath = Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force

    # A fixed reference "now" so age-based tests are deterministic and never
    # depend on the real wall clock.
    $script:Now = [datetime]::new(2026, 06, 26, 0, 0, 0, [System.DateTimeKind]::Utc)

    # Helper that builds a single artifact metadata object.
    function script:New-Artifact {
        param($Name, $Size, $AgeDays, $RunId)
        [pscustomobject]@{
            Name          = $Name
            Size          = [long]$Size
            Created       = $script:Now.AddDays(-1 * $AgeDays)
            WorkflowRunId = $RunId
        }
    }
}

Describe 'New-ArtifactObject input normalisation' {
    It 'parses ISO-8601 string dates into [datetime]' {
        $a = New-ArtifactObject -Name 'logs' -Size 100 -Created '2026-06-01T00:00:00Z' -WorkflowRunId 7
        $a.Created | Should -BeOfType [datetime]
        $a.Size    | Should -Be 100
    }

    It 'throws a meaningful error on a negative size' {
        { New-ArtifactObject -Name 'x' -Size -5 -Created $script:Now -WorkflowRunId 1 } |
            Should -Throw -ExpectedMessage '*Size must be non-negative*'
    }
}

Describe 'Invoke-ArtifactRetention - max age policy' {
    It 'deletes artifacts older than the max age and keeps newer ones' {
        $artifacts = @(
            (New-Artifact -Name 'a' -Size 100 -AgeDays 40 -RunId 1)
            (New-Artifact -Name 'b' -Size 200 -AgeDays 10 -RunId 2)
        )
        $plan = Invoke-ArtifactRetention -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:Now

        $plan.Deleted.Name  | Should -Be 'a'
        $plan.Retained.Name | Should -Be 'b'
        $plan.Summary.SpaceReclaimed | Should -Be 100
    }
}

Describe 'Invoke-ArtifactRetention - keep latest N per workflow' {
    It 'keeps the newest N artifacts in each workflow group and deletes the rest' {
        $artifacts = @(
            (New-Artifact -Name 'build' -Size 10 -AgeDays 1 -RunId 103)  # newest build
            (New-Artifact -Name 'build' -Size 10 -AgeDays 2 -RunId 102)
            (New-Artifact -Name 'build' -Size 10 -AgeDays 3 -RunId 101)  # oldest build -> deleted
            (New-Artifact -Name 'test'  -Size 10 -AgeDays 1 -RunId 201)
        )
        $plan = Invoke-ArtifactRetention -Artifacts $artifacts -KeepLatestN 2 -ReferenceDate $script:Now

        # Only the single oldest 'build' artifact exceeds keep-latest-2.
        ($plan.Deleted | Measure-Object).Count | Should -Be 1
        $plan.Deleted[0].WorkflowRunId | Should -Be 101
        ($plan.Retained | Measure-Object).Count | Should -Be 3
    }
}

Describe 'Invoke-ArtifactRetention - max total size policy' {
    It 'deletes oldest survivors until the total size is within the cap' {
        $artifacts = @(
            (New-Artifact -Name 'a' -Size 500 -AgeDays 3 -RunId 1)  # oldest -> deleted first
            (New-Artifact -Name 'b' -Size 500 -AgeDays 2 -RunId 2)
            (New-Artifact -Name 'c' -Size 500 -AgeDays 1 -RunId 3)
        )
        # Cap of 1000 bytes; total is 1500 so the single oldest must go.
        $plan = Invoke-ArtifactRetention -Artifacts $artifacts -MaxTotalSize 1000 -ReferenceDate $script:Now

        $plan.Deleted.Name | Should -Be 'a'
        $plan.Summary.SpaceReclaimed | Should -Be 500
        ($plan.Retained | Measure-Object).Count | Should -Be 2
    }
}

Describe 'Invoke-ArtifactRetention - combined policies and summary' {
    It 'unions all policies and reports an accurate summary' {
        $artifacts = @(
            (New-Artifact -Name 'build' -Size 100 -AgeDays 90 -RunId 1)  # too old
            (New-Artifact -Name 'build' -Size 100 -AgeDays 5  -RunId 2)
            (New-Artifact -Name 'build' -Size 100 -AgeDays 4  -RunId 3)
            (New-Artifact -Name 'build' -Size 100 -AgeDays 3  -RunId 4)  # newest
        )
        $plan = Invoke-ArtifactRetention -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestN 2 -ReferenceDate $script:Now

        # keep-latest-2 keeps the two newest (run4=3d, run3=4d); run2 is excess and
        # run1 is also older than 30 days, so runs 1 and 2 are deleted.
        ($plan.Deleted | Sort-Object WorkflowRunId).WorkflowRunId | Should -Be @(1, 2)
        $plan.Summary.DeletedCount  | Should -Be 2
        $plan.Summary.RetainedCount | Should -Be 2
        $plan.Summary.SpaceReclaimed | Should -Be 200
    }
}

Describe 'Invoke-ArtifactRetention - dry-run flag' {
    It 'flags the plan as dry-run without changing which artifacts are selected' {
        $artifacts = @( (New-Artifact -Name 'a' -Size 100 -AgeDays 40 -RunId 1) )
        $plan = Invoke-ArtifactRetention -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:Now -DryRun

        $plan.Summary.DryRun | Should -BeTrue
        $plan.Deleted.Name   | Should -Be 'a'
    }
}

Describe 'Invoke-ArtifactRetention - error handling' {
    It 'throws when Artifacts is null' {
        { Invoke-ArtifactRetention -Artifacts $null -MaxAgeDays 30 -ReferenceDate $script:Now } |
            Should -Throw -ExpectedMessage '*Artifacts collection cannot be null*'
    }
}
