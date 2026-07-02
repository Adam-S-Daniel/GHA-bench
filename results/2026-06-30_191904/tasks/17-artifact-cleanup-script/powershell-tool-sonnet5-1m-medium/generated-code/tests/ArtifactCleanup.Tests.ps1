#
# Pester tests for the Artifact Cleanup module.
# Red/Green TDD: each Describe block below was written before the
# corresponding implementation existed in ../ArtifactCleanup.psm1.
#
BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1'
    Import-Module $ModulePath -Force

    $FixturesDir = Join-Path $PSScriptRoot '..' 'fixtures'
    $SampleFixture = Join-Path $FixturesDir 'artifacts-sample.json'
    $SizePolicyFixture = Join-Path $FixturesDir 'artifacts-size-policy.json'
    $EmptyFixture = Join-Path $FixturesDir 'artifacts-empty.json'
    $InvalidFixture = Join-Path $FixturesDir 'artifacts-invalid.json'

    # Fixed "now" so age-based assertions are deterministic regardless of
    # when the test suite actually runs.
    $Now = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()
}

Describe 'Import-ArtifactData' {
    It 'loads all artifacts from a JSON fixture file' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $artifacts.Count | Should -Be 10
    }

    It 'parses CreatedDate as a DateTime object' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        ($artifacts | Where-Object Name -eq 'ci-build-101').CreatedDate | Should -BeOfType [datetime]
    }

    It 'preserves Name, SizeBytes and WorkflowId fields' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $item = $artifacts | Where-Object Name -eq 'docs-build-5'
        $item.SizeBytes | Should -Be 10485760
        $item.WorkflowId | Should -Be 'docs-build'
    }

    It 'returns an empty collection for an empty fixture' {
        $artifacts = @(Import-ArtifactData -Path $EmptyFixture)
        $artifacts.Count | Should -Be 0
    }

    It 'throws a meaningful error for a missing fixture file' {
        { Import-ArtifactData -Path (Join-Path $FixturesDir 'does-not-exist.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        { Import-ArtifactData -Path $InvalidFixture } | Should -Throw '*Failed to parse*'
    }
}

Describe 'Get-ArtifactRetentionPlan - max age policy' {
    It 'marks artifacts older than MaxAgeDays for deletion' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        # No KeepLatestN protection (0) so age is the only factor here.
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 45 -MaxTotalSizeBytes ([int64]::MaxValue) -KeepLatestN 0 -Now $Now

        ($plan.Artifacts | Where-Object Name -eq 'ci-build-98').Action | Should -Be 'Delete'
        ($plan.Artifacts | Where-Object Name -eq 'ci-build-98').Reason | Should -Be 'MaxAge'
        ($plan.Artifacts | Where-Object Name -eq 'release-9').Action | Should -Be 'Delete'
    }

    It 'retains artifacts within the max age window' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 45 -MaxTotalSizeBytes ([int64]::MaxValue) -KeepLatestN 0 -Now $Now

        ($plan.Artifacts | Where-Object Name -eq 'ci-build-101').Action | Should -Be 'Retain'
        ($plan.Artifacts | Where-Object Name -eq 'docs-build-5').Action | Should -Be 'Retain'
    }
}

Describe 'Get-ArtifactRetentionPlan - keep latest N per workflow' {
    It 'protects the N most recent artifacts of each workflow from age deletion' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 45 -MaxTotalSizeBytes ([int64]::MaxValue) -KeepLatestN 2 -Now $Now

        # release-9 is 181 days old but is one of the 2 latest in its workflow (only 2 exist).
        ($plan.Artifacts | Where-Object Name -eq 'release-9').Action | Should -Be 'Retain'
        ($plan.Artifacts | Where-Object Name -eq 'release-9').Reason | Should -Be 'Protected:KeepLatestN'

        # ci-build-98 (61 days old) is NOT among the 2 latest in ci-build, so age still applies.
        ($plan.Artifacts | Where-Object Name -eq 'ci-build-98').Action | Should -Be 'Delete'
        ($plan.Artifacts | Where-Object Name -eq 'ci-build-98').Reason | Should -Be 'MaxAge'
    }

    It 'never protects more than N artifacts per workflow' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 45 -MaxTotalSizeBytes ([int64]::MaxValue) -KeepLatestN 2 -Now $Now

        $protectedCiBuild = $plan.Artifacts | Where-Object { $_.WorkflowId -eq 'ci-build' -and $_.Reason -eq 'Protected:KeepLatestN' }
        $protectedCiBuild.Count | Should -Be 2
        $protectedCiBuild.Name | Should -Contain 'ci-build-101'
        $protectedCiBuild.Name | Should -Contain 'ci-build-100'
    }
}

Describe 'Get-ArtifactRetentionPlan - max total size policy' {
    It 'deletes the oldest unprotected artifacts until total size fits the budget' {
        $artifacts = Import-ArtifactData -Path $SizePolicyFixture
        # 3 artifacts x 300 bytes = 900 bytes; budget of 500 requires deleting
        # the two oldest (size-a, size-b) to get down to 300 bytes.
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 3650 -MaxTotalSizeBytes 500 -KeepLatestN 0 -Now $Now

        ($plan.Artifacts | Where-Object Name -eq 'size-a').Action | Should -Be 'Delete'
        ($plan.Artifacts | Where-Object Name -eq 'size-a').Reason | Should -Be 'MaxTotalSize'
        ($plan.Artifacts | Where-Object Name -eq 'size-b').Action | Should -Be 'Delete'
        ($plan.Artifacts | Where-Object Name -eq 'size-c').Action | Should -Be 'Retain'
    }

    It 'does not delete artifacts protected by KeepLatestN even to satisfy the size budget' {
        $artifacts = Import-ArtifactData -Path $SizePolicyFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 3650 -MaxTotalSizeBytes 1 -KeepLatestN 1 -Now $Now

        # size-c is the single latest artifact and is protected; total size
        # stays at 300 even though the budget (1 byte) can't be satisfied.
        ($plan.Artifacts | Where-Object Name -eq 'size-c').Action | Should -Be 'Retain'
        ($plan.Artifacts | Where-Object Name -eq 'size-c').Reason | Should -Be 'Protected:KeepLatestN'
        $plan.Summary.RemainingSizeBytes | Should -Be 300
    }
}

Describe 'Get-ArtifactRetentionPlan - summary' {
    It 'computes counts and reclaimed space for a combined scenario' {
        $artifacts = Import-ArtifactData -Path $SampleFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 45 -MaxTotalSizeBytes ([int64]::MaxValue) -KeepLatestN 2 -Now $Now

        # Only ci-build-98 fails age policy and is unprotected; nothing else
        # is deleted since MaxTotalSizeBytes is unbounded.
        $plan.Summary.TotalArtifacts | Should -Be 10
        $plan.Summary.DeletedCount | Should -Be 1
        $plan.Summary.RetainedCount | Should -Be 9
        $plan.Summary.SpaceReclaimedBytes | Should -Be 104857600
    }

    It 'handles an empty artifact set gracefully' {
        $plan = Get-ArtifactRetentionPlan -Artifacts @() -MaxAgeDays 45 -MaxTotalSizeBytes 1000 -KeepLatestN 2 -Now $Now
        $plan.Summary.TotalArtifacts | Should -Be 0
        $plan.Summary.DeletedCount | Should -Be 0
        $plan.Summary.SpaceReclaimedBytes | Should -Be 0
    }
}

Describe 'Get-ArtifactRetentionPlan - input validation' {
    It 'throws a meaningful error for a negative MaxAgeDays' {
        { Get-ArtifactRetentionPlan -Artifacts @() -MaxAgeDays -1 -MaxTotalSizeBytes 1000 -KeepLatestN 0 -Now $Now } |
            Should -Throw '*MaxAgeDays*'
    }

    It 'throws a meaningful error for a negative KeepLatestN' {
        { Get-ArtifactRetentionPlan -Artifacts @() -MaxAgeDays 30 -MaxTotalSizeBytes 1000 -KeepLatestN -1 -Now $Now } |
            Should -Throw '*KeepLatestN*'
    }
}

Describe 'Invoke-ArtifactCleanup - dry run vs real execution' {
    BeforeEach {
        # Remove-Artifact is the "actual deletion" side effect. It is mocked
        # here so tests never depend on (or perform) real deletions.
        Mock -CommandName Remove-Artifact -ModuleName ArtifactCleanup -MockWith { }
    }

    It 'does not call Remove-Artifact when DryRun is set' {
        $artifacts = Import-ArtifactData -Path $SizePolicyFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 3650 -MaxTotalSizeBytes 500 -KeepLatestN 0 -Now $Now

        $result = Invoke-ArtifactCleanup -Plan $plan -DryRun

        Should -Invoke -CommandName Remove-Artifact -ModuleName ArtifactCleanup -Times 0
        $result.DryRun | Should -BeTrue
        $result.DeletedNames | Should -Contain 'size-a'
    }

    It 'calls Remove-Artifact once per deleted artifact when not a dry run' {
        $artifacts = Import-ArtifactData -Path $SizePolicyFixture
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 3650 -MaxTotalSizeBytes 500 -KeepLatestN 0 -Now $Now

        $result = Invoke-ArtifactCleanup -Plan $plan

        Should -Invoke -CommandName Remove-Artifact -ModuleName ArtifactCleanup -Times 2
        $result.DryRun | Should -BeFalse
    }
}
