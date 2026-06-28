#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
    Unit tests for the Artifact Cleanup engine (ArtifactCleanup.psm1).

    These tests are written red/green TDD style: each `It` describes one
    behaviour of the retention engine. They are tagged `Unit` so the CI
    workflow can run *only* this hermetic suite inside the act container
    (the workflow-structure and act-acceptance suites need actionlint /
    Docker and must not run inside the container).

    Run locally with:  Invoke-Pester -Path tests/ArtifactCleanup.Tests.ps1
#>

BeforeAll {
    # Import the module under test fresh on every run so edits are picked up.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ArtifactCleanup.psm1'
    Import-Module $script:ModulePath -Force

    # A fixed "now" makes every age-based assertion deterministic regardless
    # of when the suite actually runs.
    $script:Now = [datetime]::new(2026, 6, 28, 0, 0, 0, [System.DateTimeKind]::Utc)

    # Small helper to build artifact objects in the canonical shape the
    # engine expects. Keeping construction in one place keeps the fixtures
    # readable and consistent across every test.
    function New-TestArtifact {
        param(
            [string]   $Name,
            [long]     $SizeBytes,
            [datetime] $CreatedAt,
            [string]   $WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowRunId = $WorkflowRunId
        }
    }
}

Describe 'Get-CleanupPlan' -Tag 'Unit' {

    Context 'with no retention policies applied' {

        BeforeAll {
            $script:Artifacts = @(
                New-TestArtifact -Name 'a' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId '1'
                New-TestArtifact -Name 'b' -SizeBytes 200 -CreatedAt $script:Now.AddDays(-2) -WorkflowRunId '1'
            )
            $script:Plan = Get-CleanupPlan -Artifact $script:Artifacts -Now $script:Now
        }

        It 'returns a plan object' {
            $script:Plan | Should -Not -BeNullOrEmpty
        }

        It 'retains every artifact when no policy is given' {
            $script:Plan.Retain.Count   | Should -Be 2
            $script:Plan.Delete.Count   | Should -Be 0
        }

        It 'reports a summary with nothing reclaimed' {
            $script:Plan.Summary.TotalArtifacts      | Should -Be 2
            $script:Plan.Summary.RetainedCount       | Should -Be 2
            $script:Plan.Summary.DeletedCount        | Should -Be 0
            $script:Plan.Summary.SpaceReclaimedBytes | Should -Be 0
            $script:Plan.Summary.TotalSizeBytes      | Should -Be 300
            $script:Plan.Summary.RetainedSizeBytes   | Should -Be 300
        }
    }

    Context 'MaxAgeDays policy' {

        BeforeAll {
            $script:Artifacts = @(
                New-TestArtifact -Name 'fresh'    -SizeBytes 100 -CreatedAt $script:Now.AddDays(-5)  -WorkflowRunId '1'
                New-TestArtifact -Name 'boundary' -SizeBytes 200 -CreatedAt $script:Now.AddDays(-30) -WorkflowRunId '1'
                New-TestArtifact -Name 'stale'    -SizeBytes 400 -CreatedAt $script:Now.AddDays(-31) -WorkflowRunId '1'
                New-TestArtifact -Name 'ancient'  -SizeBytes 800 -CreatedAt $script:Now.AddDays(-90) -WorkflowRunId '2'
            )
            $script:Plan = Get-CleanupPlan -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now
        }

        It 'deletes artifacts strictly older than the cutoff' {
            ($script:Plan.Delete.Name | Sort-Object) | Should -Be @('ancient', 'stale')
        }

        It 'retains artifacts at or under the age limit (boundary is inclusive-keep)' {
            ($script:Plan.Retain.Name | Sort-Object) | Should -Be @('boundary', 'fresh')
        }

        It 'tags each deletion with the MaxAge reason' {
            foreach ($d in $script:Plan.Delete) {
                $d.Reasons | Should -Contain 'MaxAge'
            }
        }

        It 'reclaims the summed size of the deleted artifacts' {
            $script:Plan.Summary.DeletedCount        | Should -Be 2
            $script:Plan.Summary.SpaceReclaimedBytes | Should -Be 1200   # 400 + 800
            $script:Plan.Summary.RetainedSizeBytes   | Should -Be 300    # 100 + 200
        }
    }

    Context 'KeepLatestN per workflow policy' {

        BeforeAll {
            $script:Artifacts = @(
                # Workflow 1 has 4 artifacts; the 2 newest survive.
                New-TestArtifact -Name 'w1-new'   -SizeBytes 10 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId '1'
                New-TestArtifact -Name 'w1-mid'   -SizeBytes 20 -CreatedAt $script:Now.AddDays(-2) -WorkflowRunId '1'
                New-TestArtifact -Name 'w1-old'   -SizeBytes 40 -CreatedAt $script:Now.AddDays(-3) -WorkflowRunId '1'
                New-TestArtifact -Name 'w1-older' -SizeBytes 80 -CreatedAt $script:Now.AddDays(-4) -WorkflowRunId '1'
                # Workflow 2 has exactly N artifacts; none are deleted.
                New-TestArtifact -Name 'w2-a'     -SizeBytes 16 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId '2'
                New-TestArtifact -Name 'w2-b'     -SizeBytes 32 -CreatedAt $script:Now.AddDays(-9) -WorkflowRunId '2'
                # Workflow 3 has fewer than N; it is untouched.
                New-TestArtifact -Name 'w3-a'     -SizeBytes 64 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId '3'
            )
            $script:Plan = Get-CleanupPlan -Artifact $script:Artifacts -KeepLatestN 2 -Now $script:Now
        }

        It 'keeps the N newest per workflow and deletes the rest' {
            ($script:Plan.Delete.Name | Sort-Object) | Should -Be @('w1-old', 'w1-older')
        }

        It 'leaves groups with <= N artifacts fully retained' {
            $script:Plan.Retain.Name | Should -Contain 'w2-a'
            $script:Plan.Retain.Name | Should -Contain 'w2-b'
            $script:Plan.Retain.Name | Should -Contain 'w3-a'
        }

        It 'tags each deletion with the KeepLatestN reason' {
            foreach ($d in $script:Plan.Delete) {
                $d.Reasons | Should -Contain 'KeepLatestN'
            }
        }

        It 'never deletes when KeepLatestN is large enough to cover every group' {
            $plan = Get-CleanupPlan -Artifact $script:Artifacts -KeepLatestN 99 -Now $script:Now
            $plan.Summary.DeletedCount | Should -Be 0
        }
    }

    Context 'MaxTotalSizeBytes policy' {

        BeforeAll {
            # Total = 1000 bytes across four artifacts of differing age.
            $script:Artifacts = @(
                New-TestArtifact -Name 's-newest' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1) -WorkflowRunId '1'
                New-TestArtifact -Name 's-new'    -SizeBytes 200 -CreatedAt $script:Now.AddDays(-2) -WorkflowRunId '1'
                New-TestArtifact -Name 's-old'    -SizeBytes 300 -CreatedAt $script:Now.AddDays(-3) -WorkflowRunId '1'
                New-TestArtifact -Name 's-oldest' -SizeBytes 400 -CreatedAt $script:Now.AddDays(-4) -WorkflowRunId '1'
            )
        }

        It 'deletes oldest-first until the retained total fits the cap' {
            $plan = Get-CleanupPlan -Artifact $script:Artifacts -MaxTotalSizeBytes 500 -Now $script:Now
            # 1000 -> drop s-oldest (600) -> drop s-old (300) -> stop at 300 <= 500
            ($plan.Delete.Name | Sort-Object)   | Should -Be @('s-old', 's-oldest')
            $plan.Summary.RetainedSizeBytes     | Should -Be 300
            $plan.Summary.SpaceReclaimedBytes   | Should -Be 700
        }

        It 'tags size-evicted artifacts with the MaxTotalSize reason' {
            $plan = Get-CleanupPlan -Artifact $script:Artifacts -MaxTotalSizeBytes 500 -Now $script:Now
            foreach ($d in $plan.Delete) { $d.Reasons | Should -Contain 'MaxTotalSize' }
        }

        It 'deletes nothing when the cap is >= the total size (boundary inclusive)' {
            $plan = Get-CleanupPlan -Artifact $script:Artifacts -MaxTotalSizeBytes 1000 -Now $script:Now
            $plan.Summary.DeletedCount | Should -Be 0
        }

        It 'deletes everything when the cap is zero' {
            $plan = Get-CleanupPlan -Artifact $script:Artifacts -MaxTotalSizeBytes 0 -Now $script:Now
            $plan.Summary.DeletedCount      | Should -Be 4
            $plan.Summary.RetainedSizeBytes | Should -Be 0
        }
    }

    Context 'all three policies composed together' {

        BeforeAll {
            $script:Artifacts = @(
                # Workflow A: aO is both too old AND beyond keep-latest-2.
                New-TestArtifact -Name 'aN' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1)  -WorkflowRunId 'A'
                New-TestArtifact -Name 'aM' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-2)  -WorkflowRunId 'A'
                New-TestArtifact -Name 'aO' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-50) -WorkflowRunId 'A'
                # Workflow B: both young & within keep-latest-2, so only size pressure can evict.
                New-TestArtifact -Name 'bN' -SizeBytes 300 -CreatedAt $script:Now.AddDays(-1)  -WorkflowRunId 'B'
                New-TestArtifact -Name 'bM' -SizeBytes 300 -CreatedAt $script:Now.AddDays(-3)  -WorkflowRunId 'B'
            )
            $script:Plan = Get-CleanupPlan -Artifact $script:Artifacts `
                -MaxAgeDays 30 -KeepLatestN 2 -MaxTotalSizeBytes 500 -Now $script:Now
        }

        It 'deletes the union of everything the policies object to' {
            ($script:Plan.Delete.Name | Sort-Object) | Should -Be @('aO', 'bM')
        }

        It 'accumulates every applicable reason on a single artifact' {
            $aO = $script:Plan.Delete | Where-Object Name -EQ 'aO'
            ($aO.Reasons | Sort-Object) | Should -Be @('KeepLatestN', 'MaxAge')
        }

        It 'evicts only the oldest survivor needed to satisfy the size cap' {
            $bM = $script:Plan.Delete | Where-Object Name -EQ 'bM'
            $bM.Reasons | Should -Be @('MaxTotalSize')
        }

        It 'produces a coherent summary across all policies' {
            $script:Plan.Summary.TotalArtifacts      | Should -Be 5
            $script:Plan.Summary.DeletedCount        | Should -Be 2
            $script:Plan.Summary.RetainedCount       | Should -Be 3
            $script:Plan.Summary.SpaceReclaimedBytes | Should -Be 400   # aO 100 + bM 300
            $script:Plan.Summary.RetainedSizeBytes   | Should -Be 500   # aN+aM+bN
            $script:Plan.Summary.TotalSizeBytes      | Should -Be 900
        }
    }

    Context 'input validation' {

        It 'records which policies were applied' {
            $plan = Get-CleanupPlan -Artifact @() -MaxAgeDays 10 -KeepLatestN 3
            $plan.AppliedPolicies.Keys | Should -Contain 'MaxAgeDays'
            $plan.AppliedPolicies.Keys | Should -Contain 'KeepLatestN'
            $plan.AppliedPolicies.Keys | Should -Not -Contain 'MaxTotalSizeBytes'
        }

        It 'handles an empty artifact set without error' {
            $plan = Get-CleanupPlan -Artifact @() -MaxAgeDays 10
            $plan.Summary.TotalArtifacts | Should -Be 0
            $plan.Summary.DeletedCount   | Should -Be 0
        }

        It 'throws a meaningful error on a negative MaxAgeDays' {
            { Get-CleanupPlan -Artifact @() -MaxAgeDays -1 } |
                Should -Throw -ExpectedMessage '*MaxAgeDays must be >= 0*'
        }

        It 'throws a meaningful error on a negative MaxTotalSizeBytes' {
            { Get-CleanupPlan -Artifact @() -MaxTotalSizeBytes -5 } |
                Should -Throw -ExpectedMessage '*MaxTotalSizeBytes must be >= 0*'
        }

        It 'throws when an artifact is missing a required property' {
            $bad = [pscustomobject]@{ Name = 'x'; SizeBytes = 1; CreatedAt = $script:Now }  # no WorkflowRunId
            { Get-CleanupPlan -Artifact @($bad) } |
                Should -Throw -ExpectedMessage "*missing required property 'WorkflowRunId'*"
        }

        It 'throws when CreatedAt is not a datetime' {
            $bad = [pscustomobject]@{ Name = 'x'; SizeBytes = 1; CreatedAt = 'not-a-date'; WorkflowRunId = '1' }
            { Get-CleanupPlan -Artifact @($bad) } |
                Should -Throw -ExpectedMessage '*non-datetime CreatedAt*'
        }
    }
}

Describe 'Invoke-ArtifactCleanup (dry-run / execution)' -Tag 'Unit' {

    BeforeAll {
        $script:Artifacts = @(
            New-TestArtifact -Name 'keep' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1)  -WorkflowRunId '1'
            New-TestArtifact -Name 'drop' -SizeBytes 200 -CreatedAt $script:Now.AddDays(-99) -WorkflowRunId '1'
        )
    }

    It 'never invokes the delete action in dry-run mode' {
        $called = [System.Collections.Generic.List[string]]::new()
        $plan = Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now `
            -DryRun -DeleteAction { param($a) $called.Add($a.Name) }

        $called.Count   | Should -Be 0
        $plan.DryRun    | Should -BeTrue
        # The plan still reports what *would* be deleted.
        $plan.Delete.Name | Should -Be @('drop')
    }

    It 'invokes the delete action once per deletion when not in dry-run' {
        $called = [System.Collections.Generic.List[string]]::new()
        $plan = Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now `
            -DeleteAction { param($a) $called.Add($a.Name) }

        $called.ToArray() | Should -Be @('drop')
        $plan.DryRun      | Should -BeFalse
    }

    It 'passes the full deletion record (incl. reasons) to the delete action' {
        $script:captured = $null
        Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now `
            -DeleteAction { param($a) $script:captured = $a } | Out-Null

        $script:captured.Name      | Should -Be 'drop'
        $script:captured.SizeBytes | Should -Be 200
        $script:captured.Reasons   | Should -Contain 'MaxAge'
    }

    It 'produces the same plan/summary whether or not it is a dry-run' {
        $dry  = Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now -DryRun
        $live = Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now -DeleteAction { }
        $dry.Summary.SpaceReclaimedBytes | Should -Be $live.Summary.SpaceReclaimedBytes
        $dry.Summary.DeletedCount        | Should -Be $live.Summary.DeletedCount
    }

    It 'wraps delete-action failures in a meaningful error' {
        { Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now `
            -DeleteAction { throw 'API 500' } } |
            Should -Throw -ExpectedMessage "*Failed to delete artifact 'drop'*"
    }
}

Describe 'ConvertTo-NormalizedArtifact' -Tag 'Unit' {

    It 'coerces JSON-style fields into the canonical typed shape' {
        $raw = [pscustomobject]@{
            name          = 'build-logs'
            sizeBytes     = 2048
            createdAt     = '2026-06-20T10:00:00Z'
            workflowRunId = 1001          # numeric in JSON -> string out
        }
        $n = ConvertTo-NormalizedArtifact -InputObject $raw

        $n.Name          | Should -Be 'build-logs'
        $n.SizeBytes     | Should -BeOfType [long]
        $n.SizeBytes     | Should -Be 2048
        $n.CreatedAt     | Should -BeOfType [datetime]
        $n.CreatedAt.Kind | Should -Be ([System.DateTimeKind]::Utc)
        $n.WorkflowRunId | Should -Be '1001'
    }

    It 'preserves the exact UTC instant from a Z-suffixed timestamp' {
        $raw = [pscustomobject]@{ name='x'; sizeBytes=1; createdAt='2026-01-02T03:04:05Z'; workflowRunId='9' }
        $n = ConvertTo-NormalizedArtifact -InputObject $raw
        $n.CreatedAt.ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-01-02T03:04:05Z'
    }

    It 'throws a meaningful error when a required field is absent' {
        $raw = [pscustomobject]@{ name='x'; sizeBytes=1; createdAt='2026-01-01T00:00:00Z' }  # no workflowRunId
        { ConvertTo-NormalizedArtifact -InputObject $raw } |
            Should -Throw -ExpectedMessage '*workflowRunId*'
    }
}

Describe 'Import-CleanupConfig' -Tag 'Unit' {

    BeforeAll {
        $script:GoodJson = @'
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policies": { "maxAgeDays": 30, "keepLatestN": 2, "maxTotalSizeBytes": 10000 },
  "artifacts": [
    { "name": "a", "sizeBytes": 100, "createdAt": "2026-06-20T00:00:00Z", "workflowRunId": "1" },
    { "name": "b", "sizeBytes": 200, "createdAt": "2026-01-01T00:00:00Z", "workflowRunId": "1" }
  ]
}
'@
    }

    It 'parses policies, referenceDate, dryRun and normalized artifacts' {
        $path = Join-Path $TestDrive 'good.json'
        Set-Content -Path $path -Value $script:GoodJson -Encoding utf8
        $cfg = Import-CleanupConfig -Path $path

        $cfg.Policies.MaxAgeDays        | Should -Be 30
        $cfg.Policies.KeepLatestN       | Should -Be 2
        $cfg.Policies.MaxTotalSizeBytes | Should -Be 10000
        $cfg.DryRun                     | Should -BeTrue
        $cfg.ReferenceDate.Kind         | Should -Be ([System.DateTimeKind]::Utc)
        $cfg.Artifacts.Count            | Should -Be 2
        $cfg.Artifacts[0].CreatedAt     | Should -BeOfType [datetime]
    }

    It 'omits policy keys that are absent or null in the file' {
        $json = '{ "artifacts": [], "policies": { "maxAgeDays": 7 } }'
        $path = Join-Path $TestDrive 'partial.json'
        Set-Content -Path $path -Value $json -Encoding utf8
        $cfg = Import-CleanupConfig -Path $path

        $cfg.Policies.Keys | Should -Contain 'MaxAgeDays'
        $cfg.Policies.Keys | Should -Not -Contain 'KeepLatestN'
        $cfg.Policies.Keys | Should -Not -Contain 'MaxTotalSizeBytes'
    }

    It 'defaults dryRun to $true (safe) when not specified' {
        $json = '{ "artifacts": [] }'
        $path = Join-Path $TestDrive 'nodryrun.json'
        Set-Content -Path $path -Value $json -Encoding utf8
        (Import-CleanupConfig -Path $path).DryRun | Should -BeTrue
    }

    It 'throws a clear error when the file does not exist' {
        { Import-CleanupConfig -Path (Join-Path $TestDrive 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error when the file is not valid JSON' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $path -Value '{ this is not json' -Encoding utf8
        { Import-CleanupConfig -Path $path } |
            Should -Throw -ExpectedMessage '*Failed to parse*'
    }
}

Describe 'Format-CleanupReport' -Tag 'Unit' {

    BeforeAll {
        $script:Artifacts = @(
            New-TestArtifact -Name 'keep' -SizeBytes 100 -CreatedAt $script:Now.AddDays(-1)  -WorkflowRunId '1'
            New-TestArtifact -Name 'drop' -SizeBytes 200 -CreatedAt $script:Now.AddDays(-99) -WorkflowRunId '1'
        )
        $script:Plan = Invoke-ArtifactCleanup -Artifact $script:Artifacts -MaxAgeDays 30 -Now $script:Now -DryRun
        $script:Report = Format-CleanupReport -Plan $script:Plan
    }

    It 'renders the dry-run mode banner' {
        $script:Report | Should -Match 'Mode: DRY-RUN'
    }

    It 'emits exact, greppable summary lines' {
        $script:Report | Should -Match 'TotalArtifacts: 2'
        $script:Report | Should -Match 'DeletedCount: 1'
        $script:Report | Should -Match 'RetainedCount: 1'
        $script:Report | Should -Match 'SpaceReclaimedBytes: 200'
        $script:Report | Should -Match 'RetainedSizeBytes: 100'
        $script:Report | Should -Match 'TotalSizeBytes: 300'
    }

    It 'lists each deletion with its reason' {
        $script:Report | Should -Match 'DELETE name=drop .*reasons=MaxAge'
    }
}
