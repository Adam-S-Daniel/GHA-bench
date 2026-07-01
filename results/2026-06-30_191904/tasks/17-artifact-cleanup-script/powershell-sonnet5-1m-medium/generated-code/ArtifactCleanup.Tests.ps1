# Pester tests for the ArtifactCleanup module.
# TDD log (red -> green, in order written):
#   1. Get-ArtifactRetentionPlan doesn't exist yet       -> fails to even import
#   2. empty input                                       -> smallest possible case
#   3. max-age policy                                    -> single policy in isolation
#   4. keep-latest-N-per-workflow policy                 -> second policy in isolation
#   5. max-total-size policy                             -> third policy in isolation
#   6. combined policies (no double-delete / no double-count)
#   7. input validation / error handling
#   8. Invoke-ArtifactCleanup wrapper (dry-run vs real delete)

BeforeAll {
    Import-Module "$PSScriptRoot/ArtifactCleanup.psm1" -Force

    function New-Artifact {
        param($Name, $SizeBytes, $CreatedAt, $WorkflowRunId, $WorkflowName)
        [PSCustomObject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
            WorkflowName  = $WorkflowName
        }
    }
}

Describe 'Get-ArtifactRetentionPlan' {

    Context 'empty input' {
        It 'returns an empty plan when there are no artifacts' {
            $plan = Get-ArtifactRetentionPlan -Artifacts @() -Now (Get-Date '2026-07-01')
            $plan.TotalArtifacts | Should -Be 0
            $plan.DeletedCount | Should -Be 0
            $plan.RetainedCount | Should -Be 0
            $plan.SpaceReclaimedBytes | Should -Be 0
            $plan.SpaceRetainedBytes | Should -Be 0
        }
    }

    Context 'max age policy' {
        It 'deletes artifacts older than MaxAgeDays and retains the rest' {
            $now = Get-Date '2026-07-01'
            $artifacts = @(
                New-Artifact 'old.zip' 1000 (Get-Date '2026-05-01') 'r1' 'build'
                New-Artifact 'new.zip' 2000 (Get-Date '2026-06-30') 'r2' 'build'
            )

            $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -Now $now

            $plan.ToDelete.Name | Should -Be @('old.zip')
            $plan.ToRetain.Name | Should -Be @('new.zip')
            $plan.DeletedCount | Should -Be 1
            $plan.RetainedCount | Should -Be 1
        }

        It 'does not apply the age policy when MaxAgeDays is 0 (disabled)' {
            $now = Get-Date '2026-07-01'
            $artifacts = @(
                New-Artifact 'ancient.zip' 1000 (Get-Date '2020-01-01') 'r1' 'build'
            )

            $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 0 -Now $now

            $plan.DeletedCount | Should -Be 0
        }
    }

    Context 'keep-latest-N-per-workflow policy' {
        It 'keeps only the N most recent artifacts per workflow name' {
            $now = Get-Date '2026-07-01'
            $artifacts = @(
                New-Artifact 'build-1.zip' 100 (Get-Date '2026-06-01') 'r1' 'build'
                New-Artifact 'build-2.zip' 100 (Get-Date '2026-06-15') 'r2' 'build'
                New-Artifact 'build-3.zip' 100 (Get-Date '2026-06-29') 'r3' 'build'
                New-Artifact 'test-1.zip'  100 (Get-Date '2026-06-20') 'r4' 'test'
            )

            $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -KeepLatestN 2 -Now $now

            ($plan.ToDelete.Name) | Should -Be @('build-1.zip')
            ($plan.ToRetain.Name | Sort-Object) | Should -Be @('build-2.zip', 'build-3.zip', 'test-1.zip')
        }
    }

    Context 'max total size policy' {
        It 'deletes the oldest retained artifacts until the total size fits the budget' {
            $now = Get-Date '2026-07-01'
            $artifacts = @(
                New-Artifact 'a.zip' 1000 (Get-Date '2026-06-01') 'r1' 'build'
                New-Artifact 'b.zip' 1000 (Get-Date '2026-06-15') 'r2' 'build'
                New-Artifact 'c.zip' 1000 (Get-Date '2026-06-29') 'r3' 'build'
            )

            $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxTotalSizeBytes 2000 -Now $now

            $plan.ToDelete.Name | Should -Be @('a.zip')
            $plan.SpaceReclaimedBytes | Should -Be 1000
            $plan.SpaceRetainedBytes | Should -Be 2000
        }
    }

    Context 'combined policies' {
        It 'applies age, keep-latest-N and size policies together without double counting' {
            $now = Get-Date '2026-07-01'
            $artifacts = @(
                New-Artifact 'build-old.zip' 3000000 (Get-Date '2026-05-22') 'r1' 'build' # > 30 days -> MaxAge
                New-Artifact 'build-mid.zip' 2000000 (Get-Date '2026-06-21') 'r2' 'build' # trimmed by size
                New-Artifact 'build-new.zip' 1000000 (Get-Date '2026-06-26') 'r3' 'build'
                New-Artifact 'test-mid.zip'   500000 (Get-Date '2026-06-28') 'r4' 'test'
                New-Artifact 'test-new.zip'    500000 (Get-Date '2026-06-29') 'r5' 'test'
            )

            $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -MaxTotalSizeBytes 3500000 -KeepLatestN 2 -Now $now

            ($plan.ToDelete.Name | Sort-Object) | Should -Be @('build-mid.zip', 'build-old.zip')
            ($plan.ToRetain.Name | Sort-Object) | Should -Be @('build-new.zip', 'test-mid.zip', 'test-new.zip')
            $plan.TotalArtifacts | Should -Be 5
            $plan.DeletedCount | Should -Be 2
            $plan.RetainedCount | Should -Be 3
            $plan.SpaceReclaimedBytes | Should -Be 5000000
            $plan.SpaceRetainedBytes | Should -Be 2000000
        }
    }

    Context 'input validation' {
        It 'throws a meaningful error when an artifact is missing a required property' {
            $badArtifact = [PSCustomObject]@{ Name = 'oops.zip' }

            { Get-ArtifactRetentionPlan -Artifacts @($badArtifact) -Now (Get-Date '2026-07-01') } |
                Should -Throw -ExpectedMessage '*SizeBytes*'
        }

        It 'throws a meaningful error when CreatedAt cannot be parsed as a date' {
            $badArtifact = New-Artifact 'oops.zip' 100 'not-a-date' 'r1' 'build'

            { Get-ArtifactRetentionPlan -Artifacts @($badArtifact) -Now (Get-Date '2026-07-01') } |
                Should -Throw -ExpectedMessage '*CreatedAt*'
        }
    }
}

Describe 'Invoke-ArtifactCleanup' {
    BeforeEach {
        Mock Remove-Artifact -ModuleName ArtifactCleanup { }
    }

    It 'does not call Remove-Artifact when -DryRun is specified' {
        $artifacts = @(
            New-Artifact 'old.zip' 1000 (Get-Date '2020-01-01') 'r1' 'build'
        )

        $result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays 30 -Now (Get-Date '2026-07-01') -DryRun

        $result.DryRun | Should -Be $true
        Should -Invoke Remove-Artifact -ModuleName ArtifactCleanup -Times 0
    }

    It 'calls Remove-Artifact once per artifact to delete when not a dry run' {
        $artifacts = @(
            New-Artifact 'old-1.zip' 1000 (Get-Date '2020-01-01') 'r1' 'build'
            New-Artifact 'old-2.zip' 1000 (Get-Date '2020-01-02') 'r2' 'build'
            New-Artifact 'new.zip'   1000 (Get-Date '2026-06-30') 'r3' 'build'
        )

        $result = Invoke-ArtifactCleanup -Artifacts $artifacts -MaxAgeDays 30 -Now (Get-Date '2026-07-01')

        $result.DryRun | Should -Be $false
        Should -Invoke Remove-Artifact -ModuleName ArtifactCleanup -Times 2
    }
}
