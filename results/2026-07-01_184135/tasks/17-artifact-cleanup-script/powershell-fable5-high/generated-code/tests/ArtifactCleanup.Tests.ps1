<#
.SYNOPSIS
    Pester tests for the ArtifactCleanup module.

.DESCRIPTION
    Built test-first (red/green TDD). Each Describe block below corresponds to
    one TDD cycle: the test was written first, watched fail, then the minimum
    implementation was added to ArtifactCleanup.psm1 to make it pass.

    Test fixture helpers (New-MockArtifact) generate mock artifact metadata so
    every policy can be exercised deterministically against a fixed
    reference date (no dependency on the real clock).
#>

BeforeAll {
    # Import the module under test fresh each run.
    Import-Module (Join-Path $PSScriptRoot '..' 'ArtifactCleanup.psm1') -Force

    # Fixture helper: builds a mock artifact record with the metadata shape
    # the task defines (name, size, creation date, workflow run id).
    function New-MockArtifact {
        param(
            [string]$Name,
            [long]$SizeBytes,
            [string]$CreatedAt,
            [int]$WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
        }
    }

    # Fixed "now" so age calculations are deterministic in every environment.
    $script:RefDate = [datetime]::Parse('2026-07-01T00:00:00Z').ToUniversalTime()
}

Describe 'Get-ArtifactRetentionPlan - max age policy' {
    It 'marks artifacts older than MaxAgeDays for deletion with an age reason' {
        $artifacts = @(
            New-MockArtifact -Name 'fresh' -SizeBytes 100MB -CreatedAt '2026-06-29T00:00:00Z' -WorkflowRunId 1
            New-MockArtifact -Name 'stale' -SizeBytes 200MB -CreatedAt '2026-05-01T00:00:00Z' -WorkflowRunId 2
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

        $plan.Delete.Name | Should -Be @('stale')
        $plan.Delete[0].Reason | Should -Match 'max age'
        $plan.Retain.Name | Should -Be @('fresh')
    }

    It 'retains everything when no artifact exceeds the age limit' {
        $artifacts = @(
            New-MockArtifact -Name 'a' -SizeBytes 10MB -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 1
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

        $plan.Delete | Should -BeNullOrEmpty
        $plan.Retain.Name | Should -Be @('a')
    }
}

Describe 'Get-ArtifactRetentionPlan - keep-latest-N per workflow' {
    It 'protects the N newest artifacts of each workflow run from the age policy' {
        $artifacts = @(
            # Run 100: newest is protected even though it is over the age limit.
            New-MockArtifact -Name 'r100-new' -SizeBytes 10MB -CreatedAt '2026-05-10T00:00:00Z' -WorkflowRunId 100
            New-MockArtifact -Name 'r100-old' -SizeBytes 10MB -CreatedAt '2026-05-01T00:00:00Z' -WorkflowRunId 100
            # Run 200: single artifact, over age limit, protected as its run's newest.
            New-MockArtifact -Name 'r200-only' -SizeBytes 10MB -CreatedAt '2026-04-01T00:00:00Z' -WorkflowRunId 200
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 `
            -KeepLatestPerWorkflow 1 -ReferenceDate $script:RefDate

        ($plan.Delete.Name | Sort-Object) | Should -Be @('r100-old')
        ($plan.Retain.Name | Sort-Object) | Should -Be @('r100-new', 'r200-only')
    }

    It 'protects the top N (not just 1) when KeepLatestPerWorkflow is larger' {
        $artifacts = @(
            New-MockArtifact -Name 'n1' -SizeBytes 1MB -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 500
            New-MockArtifact -Name 'n2' -SizeBytes 1MB -CreatedAt '2026-06-29T00:00:00Z' -WorkflowRunId 500
            New-MockArtifact -Name 'n3' -SizeBytes 1MB -CreatedAt '2026-06-10T00:00:00Z' -WorkflowRunId 500
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 7 `
            -KeepLatestPerWorkflow 2 -ReferenceDate $script:RefDate

        $plan.Delete.Name | Should -Be @('n3')
        ($plan.Retain.Name | Sort-Object) | Should -Be @('n1', 'n2')
    }
}

Describe 'Get-ArtifactRetentionPlan - max total size policy' {
    It 'deletes oldest unprotected artifacts until retained size fits the cap' {
        $artifacts = @(
            New-MockArtifact -Name 'newest'   -SizeBytes 150MB -CreatedAt '2026-06-29T00:00:00Z' -WorkflowRunId 1
            New-MockArtifact -Name 'middle'   -SizeBytes 120MB -CreatedAt '2026-06-20T00:00:00Z' -WorkflowRunId 1
            New-MockArtifact -Name 'oldest'   -SizeBytes 90MB  -CreatedAt '2026-06-10T00:00:00Z' -WorkflowRunId 1
        )

        # Total 360MB, cap 200MB: drop 'oldest' (90MB -> 270MB still over),
        # then 'middle' (120MB -> 150MB fits). 'newest' survives.
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxTotalSizeBytes 200MB `
            -ReferenceDate $script:RefDate

        ($plan.Delete.Name | Sort-Object) | Should -Be @('middle', 'oldest')
        $plan.Delete | ForEach-Object { $_.Reason | Should -Match 'total size' }
        $plan.Retain.Name | Should -Be @('newest')
    }

    It 'never evicts protected artifacts even when the cap cannot be met' {
        $artifacts = @(
            New-MockArtifact -Name 'big-protected' -SizeBytes 500MB -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 9
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxTotalSizeBytes 100MB `
            -KeepLatestPerWorkflow 1 -ReferenceDate $script:RefDate

        $plan.Delete | Should -BeNullOrEmpty
        $plan.Retain.Name | Should -Be @('big-protected')
    }
}

Describe 'Get-ArtifactRetentionPlan - summary' {
    It 'reports counts, reclaimed bytes and retained bytes' {
        $artifacts = @(
            New-MockArtifact -Name 'keep-a' -SizeBytes 100MB -CreatedAt '2026-06-29T00:00:00Z' -WorkflowRunId 1
            New-MockArtifact -Name 'drop-b' -SizeBytes 200MB -CreatedAt '2026-04-01T00:00:00Z' -WorkflowRunId 2
            New-MockArtifact -Name 'keep-c' -SizeBytes 50MB  -CreatedAt '2026-06-25T00:00:00Z' -WorkflowRunId 3
        )

        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

        $plan.Summary.DeletedCount | Should -Be 1
        $plan.Summary.RetainedCount | Should -Be 2
        $plan.Summary.ReclaimedBytes | Should -Be 200MB
        $plan.Summary.RetainedBytes | Should -Be 150MB
    }
}

Describe 'Get-ArtifactRetentionPlan - error handling' {
    It 'rejects an artifact record missing required metadata' {
        $bad = [pscustomobject]@{ Name = 'no-size'; CreatedAt = '2026-06-01T00:00:00Z'; WorkflowRunId = 1 }

        { Get-ArtifactRetentionPlan -Artifacts @($bad) -MaxAgeDays 30 -ReferenceDate $script:RefDate } |
            Should -Throw "*missing required property 'SizeBytes'*"
    }

    It 'rejects an unparseable creation date, naming the offending artifact' {
        $bad = [pscustomobject]@{ Name = 'bad-date'; SizeBytes = 1MB; CreatedAt = 'not-a-date'; WorkflowRunId = 1 }

        { Get-ArtifactRetentionPlan -Artifacts @($bad) -MaxAgeDays 30 -ReferenceDate $script:RefDate } |
            Should -Throw "*bad-date*invalid CreatedAt*"
    }

    It 'rejects a negative artifact size, naming the offending artifact' {
        $bad = [pscustomobject]@{ Name = 'neg'; SizeBytes = -5; CreatedAt = '2026-06-01T00:00:00Z'; WorkflowRunId = 1 }

        { Get-ArtifactRetentionPlan -Artifacts @($bad) -MaxAgeDays 30 -ReferenceDate $script:RefDate } |
            Should -Throw '*neg*negative SizeBytes*'
    }

    It 'rejects negative policy values' {
        { Get-ArtifactRetentionPlan -Artifacts @() -MaxAgeDays -1 -ReferenceDate $script:RefDate } |
            Should -Throw '*MaxAgeDays*'
    }
}

Describe 'Invoke-ArtifactCleanup - dry-run vs execute' {
    BeforeEach {
        $script:deleted = [System.Collections.Generic.List[string]]::new()
        # Mock deleter: records names instead of touching a real API, so the
        # tests can verify exactly which artifacts would be removed.
        $script:deleter = { param($artifact) $script:deleted.Add($artifact.Name) }

        $script:artifacts = @(
            New-MockArtifact -Name 'stale-1' -SizeBytes 10MB -CreatedAt '2026-01-01T00:00:00Z' -WorkflowRunId 1
            New-MockArtifact -Name 'fresh-1' -SizeBytes 10MB -CreatedAt '2026-06-30T00:00:00Z' -WorkflowRunId 1
        )
        $script:plan = Get-ArtifactRetentionPlan -Artifacts $script:artifacts -MaxAgeDays 30 `
            -ReferenceDate $script:RefDate
    }

    It 'does not invoke the deleter in dry-run mode' {
        $result = Invoke-ArtifactCleanup -Plan $script:plan -DryRun -Deleter $script:deleter

        $script:deleted.Count | Should -Be 0
        $result.DryRun | Should -BeTrue
        $result.DeletedNames | Should -Be @('stale-1')   # planned, not executed
    }

    It 'invokes the deleter once per planned deletion when executing' {
        $result = Invoke-ArtifactCleanup -Plan $script:plan -Deleter $script:deleter

        $script:deleted | Should -Be @('stale-1')
        $result.DryRun | Should -BeFalse
        $result.DeletedNames | Should -Be @('stale-1')
    }
}

Describe 'Invoke-ArtifactCleanup.ps1 CLI (fixture-driven end to end)' {
    BeforeAll {
        $script:Cli = Join-Path $PSScriptRoot '..' 'Invoke-ArtifactCleanup.ps1'
        $script:Fixtures = Join-Path $PSScriptRoot '..' 'fixtures'
    }

    It 'produces the exact dry-run plan and summary for the case1 fixture' {
        $out = & $script:Cli -ConfigPath (Join-Path $script:Fixtures 'case1.json') | Out-String

        $out | Should -Match 'Mode: DRY RUN'
        # Age policy deletes the 61-day-old build; size cap (400 MB) then
        # evicts the two oldest unprotected survivors.
        $out | Should -Match 'DELETE app-build-ancient'
        $out | Should -Match 'DELETE test-logs-old'
        $out | Should -Match 'DELETE app-build-prev'
        $out | Should -Match 'RETAIN app-build '
        $out | Should -Match 'RETAIN test-logs '
        $out | Should -Match ([regex]::Escape('Artifacts retained: 2'))
        $out | Should -Match ([regex]::Escape('Artifacts deleted: 3'))
        $out | Should -Match ([regex]::Escape('Space reclaimed: 410 MB'))
        $out | Should -Match ([regex]::Escape('Retained size: 330 MB'))
        # Dry-run must not report actual deletions.
        $out | Should -Not -Match 'Deleted artifact:'
    }

    It 'executes deletions and reports them for the case2 fixture' {
        $out = & $script:Cli -ConfigPath (Join-Path $script:Fixtures 'case2.json') | Out-String

        $out | Should -Match 'Mode: EXECUTE'
        $out | Should -Match ([regex]::Escape('Deleted artifact: nightly-3'))
        $out | Should -Match ([regex]::Escape('Deleted artifact: nightly-4'))
        $out | Should -Match ([regex]::Escape('Artifacts retained: 3'))
        $out | Should -Match ([regex]::Escape('Artifacts deleted: 2'))
        $out | Should -Match ([regex]::Escape('Space reclaimed: 150 MB'))
        $out | Should -Match ([regex]::Escape('Retained size: 610 MB'))
    }

    It 'fails with a meaningful error when the config file does not exist' {
        { & $script:Cli -ConfigPath (Join-Path $script:Fixtures 'missing.json') } |
            Should -Throw '*Config file not found*'
    }

    It 'fails with a meaningful error when the config is not valid JSON' {
        $badPath = Join-Path ([System.IO.Path]::GetTempPath()) "bad-config-$([guid]::NewGuid()).json"
        Set-Content -Path $badPath -Value '{ not json'
        try {
            { & $script:Cli -ConfigPath $badPath } | Should -Throw '*not valid JSON*'
        }
        finally {
            Remove-Item $badPath -Force -ErrorAction SilentlyContinue
        }
    }
}
