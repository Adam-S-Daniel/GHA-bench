#Requires -Modules Pester

<#
    Unit tests for the ArtifactCleanup module.
    TDD: this file is written before ArtifactCleanup.psm1 exists / has behavior.
    Run locally during development with `Invoke-Pester ./tests/ArtifactCleanup.Tests.ps1`.
    The same file also runs inside the GitHub Actions workflow (via act) so the
    pipeline itself proves the logic, per the task's "all tests run through act"
    requirement for the deliverable script.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force
}

Describe 'ConvertTo-UtcDateTime' {
    It 'returns a Kind=Utc value unchanged' {
        $value = [datetime]::SpecifyKind((Get-Date '2026-06-29'), [System.DateTimeKind]::Utc)
        (ConvertTo-UtcDateTime -Value $value).ToString('o') | Should -Be $value.ToString('o')
    }

    It 'treats a Kind=Unspecified value as already-UTC rather than local (JSON round-trip via ToString has no offset info)' {
        $value = [datetime]::SpecifyKind((Get-Date '2026-06-29'), [System.DateTimeKind]::Unspecified)
        (ConvertTo-UtcDateTime -Value $value).ToString('o') | Should -Be '2026-06-29T00:00:00.0000000Z'
    }

    It 'parses an ISO 8601 UTC string to the correct instant regardless of the host time zone' {
        (ConvertTo-UtcDateTime -Value '2026-06-29T00:00:00Z').ToString('o') | Should -Be '2026-06-29T00:00:00.0000000Z'
    }

    It 'throws a meaningful error for an unparseable string' {
        { ConvertTo-UtcDateTime -Value 'not-a-date' } | Should -Throw '*could not be parsed as a date*'
    }
}

Describe 'ConvertTo-ArtifactObject' {
    It 'normalizes a well-formed raw artifact into a typed object' {
        $raw = [PSCustomObject]@{
            name      = 'build-log-1'
            sizeBytes = 1000
            createdAt = '2026-06-29T00:00:00Z'
            workflowId = 'build'
        }

        $artifact = ConvertTo-ArtifactObject -Raw $raw

        $artifact.Name | Should -Be 'build-log-1'
        $artifact.SizeBytes | Should -Be 1000
        $artifact.WorkflowId | Should -Be 'build'
        $artifact.CreatedAt | Should -BeOfType [datetime]
    }

    It 'throws a meaningful error when Name is missing' {
        $raw = [PSCustomObject]@{ sizeBytes = 1000; createdAt = '2026-06-29T00:00:00Z'; workflowId = 'build' }
        { ConvertTo-ArtifactObject -Raw $raw } | Should -Throw '*Name*'
    }

    It 'throws a meaningful error when SizeBytes is negative' {
        $raw = [PSCustomObject]@{ name = 'x'; sizeBytes = -5; createdAt = '2026-06-29T00:00:00Z'; workflowId = 'build' }
        { ConvertTo-ArtifactObject -Raw $raw } | Should -Throw '*SizeBytes*'
    }

    It 'throws a meaningful error when CreatedAt is not a parseable date' {
        $raw = [PSCustomObject]@{ name = 'x'; sizeBytes = 5; createdAt = 'not-a-date'; workflowId = 'build' }
        { ConvertTo-ArtifactObject -Raw $raw } | Should -Throw '*CreatedAt*'
    }

    It 'throws a meaningful error when WorkflowId is missing' {
        $raw = [PSCustomObject]@{ name = 'x'; sizeBytes = 5; createdAt = '2026-06-29T00:00:00Z' }
        { ConvertTo-ArtifactObject -Raw $raw } | Should -Throw '*WorkflowId*'
    }
}

Describe 'Get-ArtifactCleanupPlan - no policy' {
    It 'retains everything and reports zero deletions when no policy limits are set' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'a'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-01'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'b'; SizeBytes = 200; CreatedAt = (Get-Date '2026-01-01'); WorkflowId = 'build' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -ReferenceDate (Get-Date '2026-07-01')

        $plan.ToDelete.Count | Should -Be 0
        $plan.ToRetain.Count | Should -Be 2
        $plan.Summary.TotalArtifacts | Should -Be 2
        $plan.Summary.DeletedCount | Should -Be 0
        $plan.Summary.RetainedCount | Should -Be 2
        $plan.Summary.BytesReclaimed | Should -Be 0
        $plan.ToRetain[0].Reason | Should -Be 'within-policy'
    }

    It 'handles an empty artifact list without throwing' {
        $plan = Get-ArtifactCleanupPlan -Artifact @() -ReferenceDate (Get-Date '2026-07-01')

        $plan.Summary.TotalArtifacts | Should -Be 0
        $plan.Summary.DeletedCount | Should -Be 0
        $plan.Summary.BytesReclaimed | Should -Be 0
    }
}

Describe 'Get-ArtifactCleanupPlan - max age policy' {
    It 'deletes artifacts older than MaxAgeDays and retains newer ones' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'fresh'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-29'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'stale'; SizeBytes = 200; CreatedAt = (Get-Date '2026-05-01'); WorkflowId = 'build' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxAgeDays 30 -ReferenceDate (Get-Date '2026-07-01')

        $plan.ToDelete.Count | Should -Be 1
        $plan.ToDelete[0].Name | Should -Be 'stale'
        $plan.ToDelete[0].Reason | Should -Be 'max-age-exceeded'
        $plan.Summary.BytesReclaimed | Should -Be 200
        $plan.ToRetain.Name | Should -Be 'fresh'
    }
}

Describe 'Get-ArtifactCleanupPlan - max total size policy' {
    It 'evicts the oldest artifacts first until the total size is under the cap' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'newest'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-30'); WorkflowId = 'deploy' }
            [PSCustomObject]@{ Name = 'middle'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-20'); WorkflowId = 'deploy' }
            [PSCustomObject]@{ Name = 'oldest'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-10'); WorkflowId = 'deploy' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxTotalSizeBytes 150 -ReferenceDate (Get-Date '2026-07-01')

        # ToDelete preserves original input order (not eviction order); both
        # 'middle' and 'oldest' are evicted to make room, 'newest' survives.
        $plan.ToDelete.Name | Should -Be @('middle', 'oldest')
        $plan.Summary.BytesReclaimed | Should -Be 200
        $plan.ToRetain.Name | Should -Be 'newest'
    }
}

Describe 'Get-ArtifactCleanupPlan - keep latest N per workflow' {
    It 'protects the newest N artifacts per workflow even if they violate age or size limits' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'build-new'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-30'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'build-old'; SizeBytes = 100; CreatedAt = (Get-Date '2026-01-01'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'test-new'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-30'); WorkflowId = 'test' }
        )

        # build-old is 181 days old (violates MaxAgeDays 30) but is the ONLY
        # artifact for a workflow that keeps at least... wait, keep-latest is 1,
        # so build-old should be protected only if it is within the newest 1.
        # Here build-new is newer, so build-old is NOT protected and should be deleted.
        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -ReferenceDate (Get-Date '2026-07-01')

        $plan.ToDelete.Name | Should -Be 'build-old'
        ($plan.ToRetain | Where-Object Name -EQ 'build-new').Reason | Should -Be 'kept-latest-N'
        ($plan.ToRetain | Where-Object Name -EQ 'test-new').Reason | Should -Be 'kept-latest-N'
    }

    It 'protects an old artifact from age-based deletion when it is within the latest N for its workflow' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'only-one'; SizeBytes = 100; CreatedAt = (Get-Date '2026-01-01'); WorkflowId = 'nightly' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -ReferenceDate (Get-Date '2026-07-01')

        $plan.ToDelete.Count | Should -Be 0
        $plan.ToRetain[0].Reason | Should -Be 'kept-latest-N'
    }
}

Describe 'Get-ArtifactCleanupPlan - input validation' {
    It 'throws a meaningful error for a negative MaxAgeDays' {
        { Get-ArtifactCleanupPlan -Artifact @() -MaxAgeDays -1 } | Should -Throw '*MaxAgeDays*'
    }

    It 'throws a meaningful error for a negative MaxTotalSizeBytes' {
        { Get-ArtifactCleanupPlan -Artifact @() -MaxTotalSizeBytes -1 } | Should -Throw '*MaxTotalSizeBytes*'
    }

    It 'throws a meaningful error for a negative KeepLatestPerWorkflow' {
        { Get-ArtifactCleanupPlan -Artifact @() -KeepLatestPerWorkflow -1 } | Should -Throw '*KeepLatestPerWorkflow*'
    }
}

Describe 'Remove-Artifact' {
    It 'reports the artifact as deleted' {
        $artifact = [PSCustomObject]@{ Name = 'x'; SizeBytes = 10; CreatedAt = (Get-Date); WorkflowId = 'build' }
        $result = Remove-Artifact -Artifact $artifact
        $result.Name | Should -Be 'x'
        $result.Deleted | Should -Be $true
    }
}

Describe 'Invoke-ArtifactCleanup' {
    BeforeAll {
        $script:artifacts = @(
            [PSCustomObject]@{ Name = 'fresh'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-29'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'stale'; SizeBytes = 200; CreatedAt = (Get-Date '2026-05-01'); WorkflowId = 'build' }
        )
    }

    It 'actually removes artifacts marked for deletion when not a dry run' {
        Mock -ModuleName ArtifactCleanup Remove-Artifact { param($Artifact) [PSCustomObject]@{ Name = $Artifact.Name; Deleted = $true } }

        $result = Invoke-ArtifactCleanup -Artifact $script:artifacts -MaxAgeDays 30 -ReferenceDate (Get-Date '2026-07-01')

        Should -Invoke -ModuleName ArtifactCleanup Remove-Artifact -Times 1 -Exactly
        $result.Plan.Summary.DeletedCount | Should -Be 1
        $result.ArtifactsActuallyRemoved | Should -Be 1
        $result.DryRun | Should -Be $false
    }

    It 'does not remove anything in dry-run mode, but still reports the plan' {
        Mock -ModuleName ArtifactCleanup Remove-Artifact { param($Artifact) [PSCustomObject]@{ Name = $Artifact.Name; Deleted = $true } }

        $result = Invoke-ArtifactCleanup -Artifact $script:artifacts -MaxAgeDays 30 -ReferenceDate (Get-Date '2026-07-01') -DryRun

        Should -Invoke -ModuleName ArtifactCleanup Remove-Artifact -Times 0 -Exactly
        $result.Plan.Summary.DeletedCount | Should -Be 1
        $result.ArtifactsActuallyRemoved | Should -Be 0
        $result.DryRun | Should -Be $true
    }
}

Describe 'ConvertTo-ArtifactObject - boundary values' {
    It 'accepts a SizeBytes of exactly zero' {
        $raw = [PSCustomObject]@{ name = 'empty'; sizeBytes = 0; createdAt = '2026-06-29T00:00:00Z'; workflowId = 'build' }
        { ConvertTo-ArtifactObject -Raw $raw } | Should -Not -Throw
    }

    It 'preserves the correct UTC instant when CreatedAt arrives pre-parsed as a [datetime] (as ConvertFrom-Json produces for ISO 8601 strings)' {
        # ConvertFrom-Json auto-converts ISO 8601 date strings into [datetime]
        # objects with Kind=Utc *before* ConvertTo-ArtifactObject ever sees
        # them. Naively doing [string]$value then re-parsing loses the "Z"
        # and reinterprets the naive string as local time, silently shifting
        # the value by the host's UTC offset.
        $configLikeJson = '{"createdAt":"2026-06-29T00:00:00Z"}' | ConvertFrom-Json
        $preParsed = $configLikeJson.createdAt
        $preParsed | Should -BeOfType [datetime]
        $preParsed.Kind | Should -Be ([System.DateTimeKind]::Utc)

        $raw = [PSCustomObject]@{ name = 'x'; sizeBytes = 1; createdAt = $preParsed; workflowId = 'build' }
        $artifact = ConvertTo-ArtifactObject -Raw $raw

        $artifact.CreatedAt.ToUniversalTime().ToString('o') | Should -Be '2026-06-29T00:00:00.0000000Z'
    }
}

Describe 'Get-ArtifactCleanupPlan - boundary values' {
    It 'retains an artifact whose age is exactly MaxAgeDays (age must exceed, not just reach, the limit)' {
        $artifacts = @(
            [PSCustomObject]@{ Name = 'exactly-30-days'; SizeBytes = 100; CreatedAt = (Get-Date '2026-06-01'); WorkflowId = 'build' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxAgeDays 30 -ReferenceDate (Get-Date '2026-07-01')

        $plan.ToDelete.Count | Should -Be 0
        $plan.ToRetain[0].Reason | Should -Be 'within-policy'
    }
}

Describe 'Get-ArtifactCleanupPlan - combined policy precedence' {
    It 'applies keep-latest-N protection, then max-age, then max-total-size in that order' {
        # Mirrors the "age-and-size" CI fixture scenario: two workflows, each
        # keeping its 2 newest artifacts; old unprotected build artifacts are
        # deleted by age; the survivor set (300MB) then fits under the
        # 500MB cap so no size-based eviction is needed.
        $artifacts = @(
            [PSCustomObject]@{ Name = 'build-log-1'; SizeBytes = 100000000; CreatedAt = (Get-Date '2026-06-29'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'build-log-2'; SizeBytes = 100000000; CreatedAt = (Get-Date '2026-06-20'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'build-log-3'; SizeBytes = 150000000; CreatedAt = (Get-Date '2026-05-01'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'build-log-4'; SizeBytes = 150000000; CreatedAt = (Get-Date '2026-04-01'); WorkflowId = 'build' }
            [PSCustomObject]@{ Name = 'test-report-1'; SizeBytes = 50000000; CreatedAt = (Get-Date '2026-06-30'); WorkflowId = 'test' }
            [PSCustomObject]@{ Name = 'test-report-2'; SizeBytes = 50000000; CreatedAt = (Get-Date '2026-01-01'); WorkflowId = 'test' }
        )

        $plan = Get-ArtifactCleanupPlan -Artifact $artifacts -MaxAgeDays 30 -MaxTotalSizeBytes 500000000 `
            -KeepLatestPerWorkflow 2 -ReferenceDate (Get-Date '2026-07-01')

        $plan.Summary.TotalArtifacts | Should -Be 6
        $plan.Summary.DeletedCount | Should -Be 2
        $plan.Summary.RetainedCount | Should -Be 4
        $plan.Summary.BytesReclaimed | Should -Be 300000000
        ($plan.ToDelete | Sort-Object Name).Name | Should -Be @('build-log-3', 'build-log-4')
        # test-report-2 is 181 days old (violates MaxAgeDays) but is kept
        # because its workflow only has 2 artifacts total.
        ($plan.ToRetain | Where-Object Name -EQ 'test-report-2').Reason | Should -Be 'kept-latest-N'
    }
}
