# ArtifactCleanup.Tests.ps1
#
# Pester tests for the artifact retention / cleanup planner.
#
# These tests were written red/green TDD style: each describes a single
# behaviour of Get-ArtifactCleanupPlan, was written to fail first, and the
# implementation in ArtifactCleanup.psm1 was grown to make them pass.

BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    Import-Module (Join-Path $here 'ArtifactCleanup.psm1') -Force

    # Helper to build a mock artifact. Dates are kept relative to a fixed
    # reference "now" so tests are deterministic and never depend on the wall
    # clock of the machine running them.
    function New-MockArtifact {
        param(
            [string]   $Name,
            [long]     $SizeBytes,
            [datetime] $CreatedAt,
            [long]     $WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
        }
    }

    # Fixed reference point so "age" maths is stable.
    $script:Now = [datetime]'2026-06-01T00:00:00Z'
}

Describe 'Get-ArtifactCleanupPlan' {

    Context 'Input validation' {
        It 'throws a meaningful error when Artifacts is $null' {
            { Get-ArtifactCleanupPlan -Artifacts $null -Now $script:Now } |
                Should -Throw -ExpectedMessage '*Artifacts*'
        }

        It 'returns an empty plan for an empty artifact list' {
            $plan = Get-ArtifactCleanupPlan -Artifacts @() -Now $script:Now
            $plan.Summary.TotalArtifacts | Should -Be 0
            $plan.Summary.DeletedCount   | Should -Be 0
            $plan.Summary.RetainedCount  | Should -Be 0
            $plan.ToDelete.Count         | Should -Be 0
        }

        It 'throws when an artifact is missing a required property' {
            $bad = [pscustomobject]@{ Name = 'x'; SizeBytes = 1 }  # no CreatedAt
            { Get-ArtifactCleanupPlan -Artifacts @($bad) -Now $script:Now } |
                Should -Throw -ExpectedMessage '*CreatedAt*'
        }
    }

    Context 'No policies configured' {
        It 'retains every artifact when no policy is supplied' {
            $artifacts = @(
                New-MockArtifact -Name 'a' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1)   -WorkflowRunId 1
                New-MockArtifact -Name 'b' -SizeBytes 200 -CreatedAt $script:Now.AddDays(-400) -WorkflowRunId 2
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -Now $script:Now
            $plan.Summary.RetainedCount | Should -Be 2
            $plan.Summary.DeletedCount  | Should -Be 0
        }
    }

    Context 'Max-age policy' {
        It 'deletes artifacts older than MaxAgeDays and keeps newer ones' {
            $artifacts = @(
                New-MockArtifact -Name 'young' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-5)  -WorkflowRunId 1
                New-MockArtifact -Name 'old'   -SizeBytes 100 -CreatedAt $script:Now.AddDays(-40) -WorkflowRunId 1
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now

            $plan.ToDelete.Name | Should -Be 'old'
            $plan.ToRetain.Name | Should -Be 'young'
            ($plan.ToDelete | Where-Object Name -eq 'old').Reason | Should -Match 'age'
        }

        It 'treats an artifact exactly at the age boundary as retained' {
            $artifacts = @(
                New-MockArtifact -Name 'boundary' -SizeBytes 1 -CreatedAt $script:Now.AddDays(-30) -WorkflowRunId 1
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $script:Now
            $plan.Summary.RetainedCount | Should -Be 1
        }
    }

    Context 'Keep-latest-N-per-workflow policy' {
        It 'keeps only the newest N artifacts within each workflow run id' {
            $artifacts = @(
                # Workflow 1 has 3 artifacts; keep 2 newest.
                New-MockArtifact -Name 'w1-newest' -SizeBytes 10 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId 1
                New-MockArtifact -Name 'w1-mid'    -SizeBytes 10 -CreatedAt $script:Now.AddDays(-2) -WorkflowRunId 1
                New-MockArtifact -Name 'w1-oldest' -SizeBytes 10 -CreatedAt $script:Now.AddDays(-3) -WorkflowRunId 1
                # Workflow 2 has only 1 artifact; it survives.
                New-MockArtifact -Name 'w2-only'   -SizeBytes 10 -CreatedAt $script:Now.AddDays(-9) -WorkflowRunId 2
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 2 -Now $script:Now

            $plan.ToDelete.Name | Should -Be 'w1-oldest'
            ($plan.ToDelete | Where-Object Name -eq 'w1-oldest').Reason | Should -Match 'keep-latest'
            $plan.ToRetain.Name | Should -Contain 'w2-only'
        }
    }

    Context 'Max-total-size policy' {
        It 'deletes oldest artifacts until retained size is within the cap' {
            $artifacts = @(
                New-MockArtifact -Name 'new'  -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId 1
                New-MockArtifact -Name 'mid'  -SizeBytes 100 -CreatedAt $script:Now.AddDays(-2) -WorkflowRunId 1
                New-MockArtifact -Name 'old'  -SizeBytes 100 -CreatedAt $script:Now.AddDays(-3) -WorkflowRunId 1
            )
            # Cap of 250 bytes -> can keep two 100-byte artifacts, must drop one.
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 250 -Now $script:Now

            $plan.Summary.RetainedSizeBytes | Should -BeLessOrEqual 250
            $plan.ToDelete.Name | Should -Be 'old'
            ($plan.ToDelete | Where-Object Name -eq 'old').Reason | Should -Match 'size'
        }
    }

    Context 'Combined policies and summary' {
        It 'applies all policies and reports an accurate summary' {
            $artifacts = @(
                New-MockArtifact -Name 'keep'       -SizeBytes 50  -CreatedAt $script:Now.AddDays(-1)  -WorkflowRunId 1
                New-MockArtifact -Name 'too-old'    -SizeBytes 50  -CreatedAt $script:Now.AddDays(-90) -WorkflowRunId 1
                New-MockArtifact -Name 'extra-w2-a' -SizeBytes 50  -CreatedAt $script:Now.AddDays(-2)  -WorkflowRunId 2
                New-MockArtifact -Name 'extra-w2-b' -SizeBytes 50  -CreatedAt $script:Now.AddDays(-3)  -WorkflowRunId 2
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts `
                -MaxAgeDays 30 -KeepLatestN 1 -Now $script:Now

            $plan.Summary.TotalArtifacts      | Should -Be 4
            $plan.Summary.DeletedCount        | Should -Be 2   # too-old + extra-w2-b
            $plan.Summary.RetainedCount       | Should -Be 2
            $plan.Summary.SpaceReclaimedBytes | Should -Be 100
            $plan.ToDelete.Name | Should -Contain 'too-old'
            $plan.ToDelete.Name | Should -Contain 'extra-w2-b'
        }

        It 'never lists an artifact in both delete and retain sets' {
            $artifacts = @(
                New-MockArtifact -Name 'a' -SizeBytes 10 -CreatedAt $script:Now.AddDays(-100) -WorkflowRunId 1
                New-MockArtifact -Name 'b' -SizeBytes 10 -CreatedAt $script:Now.AddDays(-1)   -WorkflowRunId 1
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 10 -KeepLatestN 1 -Now $script:Now
            $deleteNames = $plan.ToDelete.Name
            $retainNames = $plan.ToRetain.Name
            ($deleteNames | Where-Object { $_ -in $retainNames }) | Should -BeNullOrEmpty
        }
    }

    Context 'Dry-run mode' {
        It 'marks the plan as dry-run and never reports executed deletions' {
            $artifacts = @(
                New-MockArtifact -Name 'old' -SizeBytes 10 -CreatedAt $script:Now.AddDays(-100) -WorkflowRunId 1
            )
            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 10 -Now $script:Now -DryRun
            $plan.DryRun            | Should -BeTrue
            $plan.Summary.Executed  | Should -BeFalse
            $plan.ToDelete.Count    | Should -Be 1
        }

        It 'defaults DryRun to false when the switch is not supplied' {
            $plan = Get-ArtifactCleanupPlan -Artifacts @() -Now $script:Now
            $plan.DryRun | Should -BeFalse
        }
    }
}
