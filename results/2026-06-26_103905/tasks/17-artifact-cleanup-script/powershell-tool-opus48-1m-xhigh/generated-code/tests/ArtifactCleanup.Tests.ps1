# ArtifactCleanup.Tests.ps1
#
# Pester test suite for the artifact-cleanup tooling, written test-first
# following red/green/refactor TDD. Each Context block was introduced as a
# failing test before the corresponding behaviour existed in ArtifactCleanup.psm1.
#
# Run with: Invoke-Pester -Path tests

BeforeAll {
    # Import the module under test. Resolve the path relative to this test file
    # so the suite runs from any working directory (CI, act container, dev box).
    $ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'ArtifactCleanup.psm1'
    Import-Module $ModulePath -Force

    # A fixed reference "now" makes age-based policies deterministic in tests.
    $script:RefDate = [datetime]'2026-06-28T00:00:00Z'

    # Helper to build an artifact object with sensible defaults so individual
    # tests only specify the fields they care about.
    function New-TestArtifact {
        param(
            [string]$Name,
            [long]$SizeBytes = 1MB,
            [datetime]$CreatedAt = $script:RefDate,
            [long]$WorkflowRunId = 1
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

    Context 'when no retention policies are supplied' {
        It 'retains every artifact' {
            $artifacts = @(
                New-TestArtifact -Name 'a'
                New-TestArtifact -Name 'b'
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -ReferenceDate $script:RefDate

            $plan.Summary.RetainedCount | Should -Be 2
            $plan.Summary.DeletedCount  | Should -Be 0
        }

        It 'produces a per-artifact plan item for every input artifact' {
            $artifacts = @(
                New-TestArtifact -Name 'a' -SizeBytes 100
                New-TestArtifact -Name 'b' -SizeBytes 200
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -ReferenceDate $script:RefDate

            $plan.Items.Count | Should -Be 2
            ($plan.Items | Where-Object Action -eq 'Retain').Count | Should -Be 2
            # Each item carries a human-readable reason explaining the decision.
            $plan.Items | ForEach-Object { $_.Reason | Should -Not -BeNullOrEmpty }
        }

        It 'reports zero reclaimed space and the full retained size' {
            $artifacts = @(
                New-TestArtifact -Name 'a' -SizeBytes 100
                New-TestArtifact -Name 'b' -SizeBytes 200
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -ReferenceDate $script:RefDate

            $plan.Summary.TotalArtifacts      | Should -Be 2
            $plan.Summary.SpaceReclaimedBytes | Should -Be 0
            $plan.Summary.RetainedSizeBytes   | Should -Be 300
        }
    }

    Context 'max-age policy' {
        It 'deletes artifacts older than the maximum age and keeps newer ones' {
            $artifacts = @(
                New-TestArtifact -Name 'old'    -SizeBytes 100 -CreatedAt $script:RefDate.AddDays(-40)
                New-TestArtifact -Name 'recent' -SizeBytes 200 -CreatedAt $script:RefDate.AddDays(-10)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'old').Action    | Should -Be 'Delete'
            ($plan.Items | Where-Object Name -eq 'recent').Action | Should -Be 'Retain'
            $plan.Summary.DeletedCount        | Should -Be 1
            $plan.Summary.SpaceReclaimedBytes | Should -Be 100
        }

        It 'treats an artifact exactly at the age boundary as still within retention' {
            # Exactly 30 days old with a 30-day max should be kept (boundary is inclusive).
            $artifacts = @(
                New-TestArtifact -Name 'boundary' -CreatedAt $script:RefDate.AddDays(-30)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'boundary').Action | Should -Be 'Retain'
        }

        It 'records the age as the deletion reason' {
            $artifacts = @(
                New-TestArtifact -Name 'old' -CreatedAt $script:RefDate.AddDays(-90)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'old').Reason | Should -Match 'age'
        }
    }

    Context 'keep-latest-N-per-workflow policy' {
        It 'keeps the N most-recent artifacts per workflow run and deletes the rest' {
            # One workflow (run id 7) with three artifacts; keep the latest 2.
            $artifacts = @(
                New-TestArtifact -Name 'w7-oldest' -WorkflowRunId 7 -CreatedAt $script:RefDate.AddDays(-3)
                New-TestArtifact -Name 'w7-middle' -WorkflowRunId 7 -CreatedAt $script:RefDate.AddDays(-2)
                New-TestArtifact -Name 'w7-newest' -WorkflowRunId 7 -CreatedAt $script:RefDate.AddDays(-1)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 2 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'w7-newest').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'w7-middle').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'w7-oldest').Action | Should -Be 'Delete'
            $plan.Summary.DeletedCount | Should -Be 1
        }

        It 'applies the keep-latest count independently to each workflow run' {
            # Two workflows; each should keep its own newest artifact.
            $artifacts = @(
                New-TestArtifact -Name 'w1-old' -WorkflowRunId 1 -CreatedAt $script:RefDate.AddDays(-5)
                New-TestArtifact -Name 'w1-new' -WorkflowRunId 1 -CreatedAt $script:RefDate.AddDays(-1)
                New-TestArtifact -Name 'w2-old' -WorkflowRunId 2 -CreatedAt $script:RefDate.AddDays(-6)
                New-TestArtifact -Name 'w2-new' -WorkflowRunId 2 -CreatedAt $script:RefDate.AddDays(-2)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 1 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'w1-new').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'w2-new').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'w1-old').Action | Should -Be 'Delete'
            ($plan.Items | Where-Object Name -eq 'w2-old').Action | Should -Be 'Delete'
            $plan.Summary.DeletedCount | Should -Be 2
        }

        It 'still deletes a newest-N artifact that also violates max-age (union of policies)' {
            # keep-latest-1 alone would keep the newest, but it is itself older
            # than the max age, so the union of policies removes both.
            $artifacts = @(
                New-TestArtifact -Name 'ancient-but-newest' -WorkflowRunId 9 -CreatedAt $script:RefDate.AddDays(-100)
                New-TestArtifact -Name 'even-older'         -WorkflowRunId 9 -CreatedAt $script:RefDate.AddDays(-200)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 1 -MaxAgeDays 30 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'ancient-but-newest').Action | Should -Be 'Delete'
            ($plan.Items | Where-Object Name -eq 'even-older').Action         | Should -Be 'Delete'
            $plan.Summary.DeletedCount | Should -Be 2
        }

        It 'keeps a newest-N artifact that is within the max age while still trimming the rest' {
            # Newest two are recent (kept by both policies); the third is beyond
            # keep-latest-2 and gets deleted.
            $artifacts = @(
                New-TestArtifact -Name 'r5-newest' -WorkflowRunId 5 -CreatedAt $script:RefDate.AddDays(-1)
                New-TestArtifact -Name 'r5-second' -WorkflowRunId 5 -CreatedAt $script:RefDate.AddDays(-2)
                New-TestArtifact -Name 'r5-third'  -WorkflowRunId 5 -CreatedAt $script:RefDate.AddDays(-3)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestPerWorkflow 2 -MaxAgeDays 30 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'r5-newest').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'r5-second').Action | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'r5-third').Action  | Should -Be 'Delete'
        }
    }

    Context 'max-total-size policy' {
        It 'deletes the oldest artifacts first until the retained total fits the cap' {
            # 3 x 100-byte artifacts (=300) with a 250-byte cap: drop the oldest (100)
            # so the retained total becomes 200, which is under the cap.
            $artifacts = @(
                New-TestArtifact -Name 'old'    -SizeBytes 100 -CreatedAt $script:RefDate.AddDays(-3)
                New-TestArtifact -Name 'mid'    -SizeBytes 100 -CreatedAt $script:RefDate.AddDays(-2)
                New-TestArtifact -Name 'newest' -SizeBytes 100 -CreatedAt $script:RefDate.AddDays(-1)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 250 -ReferenceDate $script:RefDate

            ($plan.Items | Where-Object Name -eq 'old').Action    | Should -Be 'Delete'
            ($plan.Items | Where-Object Name -eq 'mid').Action    | Should -Be 'Retain'
            ($plan.Items | Where-Object Name -eq 'newest').Action | Should -Be 'Retain'
            $plan.Summary.RetainedSizeBytes   | Should -Be 200
            $plan.Summary.SpaceReclaimedBytes | Should -Be 100
        }

        It 'does nothing when the total is already within the cap' {
            $artifacts = @(
                New-TestArtifact -Name 'a' -SizeBytes 100
                New-TestArtifact -Name 'b' -SizeBytes 100
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 1000 -ReferenceDate $script:RefDate

            $plan.Summary.DeletedCount | Should -Be 0
        }

        It 'warns when the cap is smaller than the largest individual artifact' {
            # No single artifact (500) can ever fit under a 100-byte cap, so the
            # plan deletes everything down to the cap and records a warning.
            $artifacts = @(
                New-TestArtifact -Name 'p1' -SizeBytes 500 -CreatedAt $script:RefDate.AddDays(-2)
                New-TestArtifact -Name 'p2' -SizeBytes 500 -CreatedAt $script:RefDate.AddDays(-1)
            )

            $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 100 -ReferenceDate $script:RefDate

            $plan.Summary.DeletedCount      | Should -Be 2
            $plan.Summary.RetainedSizeBytes | Should -Be 0
            $plan.Summary.Warnings          | Should -Not -BeNullOrEmpty
            ($plan.Summary.Warnings -join ' ') | Should -Match 'largest'
        }
    }

    Context 'edge cases' {
        It 'handles an empty artifact list without error' {
            $plan = Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays 30 -ReferenceDate $script:RefDate

            $plan.Summary.TotalArtifacts      | Should -Be 0
            $plan.Summary.DeletedCount        | Should -Be 0
            $plan.Summary.SpaceReclaimedBytes | Should -Be 0
        }
    }
}

Describe 'Import-ArtifactData' {

    BeforeAll {
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-tests-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TempRoot) { Remove-Item $script:TempRoot -Recurse -Force }
    }

    It 'loads well-formed artifact JSON into typed objects' {
        $path = Join-Path $script:TempRoot 'good.json'
        @'
[
  { "Name": "a", "SizeBytes": 1024, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 },
  { "Name": "b", "SizeBytes": 2048, "CreatedAt": "2026-06-02T00:00:00Z", "WorkflowRunId": 2 }
]
'@ | Set-Content -Path $path -Encoding utf8

        $artifacts = Import-ArtifactData -Path $path

        $artifacts.Count | Should -Be 2
        $artifacts[0].Name | Should -Be 'a'
        $artifacts[0].SizeBytes | Should -BeOfType [long]
        $artifacts[0].CreatedAt | Should -BeOfType [datetime]
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-ArtifactData -Path (Join-Path $script:TempRoot 'missing.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error on malformed JSON' {
        $path = Join-Path $script:TempRoot 'bad.json'
        'this is { not json' | Set-Content -Path $path -Encoding utf8

        { Import-ArtifactData -Path $path } | Should -Throw -ExpectedMessage '*JSON*'
    }

    It 'throws a meaningful error when a required field is missing' {
        $path = Join-Path $script:TempRoot 'incomplete.json'
        '[ { "Name": "a", "SizeBytes": 10 } ]' | Set-Content -Path $path -Encoding utf8

        { Import-ArtifactData -Path $path } | Should -Throw -ExpectedMessage '*CreatedAt*'
    }

    It 'throws a meaningful error when a size is negative' {
        $path = Join-Path $script:TempRoot 'negative.json'
        '[ { "Name": "a", "SizeBytes": -5, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 } ]' |
            Set-Content -Path $path -Encoding utf8

        { Import-ArtifactData -Path $path } | Should -Throw -ExpectedMessage '*SizeBytes*'
    }
}

Describe 'Import-CleanupScenario' {

    BeforeAll {
        $script:ScenRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("scenario-tests-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:ScenRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:ScenRoot) { Remove-Item $script:ScenRoot -Recurse -Force }
    }

    It 'parses a full scenario file into policy, mode, reference date and artifacts' {
        $path = Join-Path $script:ScenRoot 'full.json'
        @'
{
  "referenceDate": "2026-06-28T00:00:00Z",
  "dryRun": true,
  "policy": { "maxAgeDays": 30, "maxTotalSizeBytes": 5000, "keepLatestPerWorkflow": 2 },
  "artifacts": [
    { "Name": "a", "SizeBytes": 100, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $scenario = Import-CleanupScenario -Path $path

        $scenario.ReferenceDate | Should -BeOfType [datetime]
        $scenario.DryRun         | Should -BeTrue
        $scenario.Policy.MaxAgeDays            | Should -Be 30
        $scenario.Policy.MaxTotalSizeBytes     | Should -Be 5000
        $scenario.Policy.KeepLatestPerWorkflow | Should -Be 2
        $scenario.Artifacts.Count | Should -Be 1
        $scenario.Artifacts[0].CreatedAt | Should -BeOfType [datetime]
    }

    It 'defaults absent policy fields to null (policy disabled)' {
        $path = Join-Path $script:ScenRoot 'no-policy.json'
        @'
{
  "artifacts": [
    { "Name": "a", "SizeBytes": 100, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 }
  ]
}
'@ | Set-Content -Path $path -Encoding utf8

        $scenario = Import-CleanupScenario -Path $path

        $scenario.Policy.MaxAgeDays            | Should -BeNullOrEmpty
        $scenario.Policy.MaxTotalSizeBytes     | Should -BeNullOrEmpty
        $scenario.Policy.KeepLatestPerWorkflow | Should -BeNullOrEmpty
    }

    It 'defaults dryRun to true when not specified (safe by default)' {
        $path = Join-Path $script:ScenRoot 'no-dryrun.json'
        '{ "artifacts": [ { "Name": "a", "SizeBytes": 1, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 } ] }' |
            Set-Content -Path $path -Encoding utf8

        (Import-CleanupScenario -Path $path).DryRun | Should -BeTrue
    }

    It 'throws a meaningful error when the artifacts array is missing' {
        $path = Join-Path $script:ScenRoot 'no-artifacts.json'
        '{ "policy": { "maxAgeDays": 30 } }' | Set-Content -Path $path -Encoding utf8

        { Import-CleanupScenario -Path $path } | Should -Throw -ExpectedMessage '*artifacts*'
    }

    It 'reuses artifact validation (rejects a negative size)' {
        $path = Join-Path $script:ScenRoot 'bad-artifact.json'
        '{ "artifacts": [ { "Name": "a", "SizeBytes": -1, "CreatedAt": "2026-06-01T00:00:00Z", "WorkflowRunId": 1 } ] }' |
            Set-Content -Path $path -Encoding utf8

        { Import-CleanupScenario -Path $path } | Should -Throw -ExpectedMessage '*SizeBytes*'
    }
}

Describe 'Format-Bytes' {
    It 'formats <bytes> bytes as <expected>' -TestCases @(
        @{ Bytes = 0;          Expected = '0 B' }
        @{ Bytes = 512;        Expected = '512 B' }
        @{ Bytes = 1024;       Expected = '1 KB' }
        @{ Bytes = 1536;       Expected = '1.5 KB' }
        @{ Bytes = 1048576;    Expected = '1 MB' }
        @{ Bytes = 1073741824; Expected = '1 GB' }
    ) {
        param($Bytes, $Expected)
        Format-Bytes -Bytes $Bytes | Should -Be $Expected
    }
}

Describe 'Invoke-ArtifactCleanup' {

    BeforeAll {
        $script:CliRefDate = [datetime]'2026-06-28T00:00:00Z'
        $script:CliArtifacts = @(
            [pscustomobject]@{ Name = 'old';    SizeBytes = 100; CreatedAt = $script:CliRefDate.AddDays(-90); WorkflowRunId = 1 }
            [pscustomobject]@{ Name = 'recent'; SizeBytes = 200; CreatedAt = $script:CliRefDate.AddDays(-5);  WorkflowRunId = 1 }
        )
    }

    It 'marks the plan as a dry run when -DryRun is supplied' {
        $plan = Invoke-ArtifactCleanup -Artifacts $script:CliArtifacts -MaxAgeDays 30 -DryRun -ReferenceDate $script:CliRefDate
        $plan.DryRun | Should -BeTrue
    }

    It 'marks the plan as not a dry run when -DryRun is omitted' {
        $plan = Invoke-ArtifactCleanup -Artifacts $script:CliArtifacts -MaxAgeDays 30 -ReferenceDate $script:CliRefDate
        $plan.DryRun | Should -BeFalse
    }

    It 'records the applied policy on the plan' {
        $plan = Invoke-ArtifactCleanup -Artifacts $script:CliArtifacts -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -ReferenceDate $script:CliRefDate
        $plan.Policy.MaxAgeDays            | Should -Be 30
        $plan.Policy.KeepLatestPerWorkflow | Should -Be 1
    }

    It 'computes the same deletion decisions as Get-ArtifactCleanupPlan' {
        $plan = Invoke-ArtifactCleanup -Artifacts $script:CliArtifacts -MaxAgeDays 30 -ReferenceDate $script:CliRefDate
        $plan.Summary.DeletedCount        | Should -Be 1
        $plan.Summary.SpaceReclaimedBytes | Should -Be 100
    }
}

Describe 'CLI integration (Invoke-ArtifactCleanupCli.ps1)' {
    # Drives the real CLI end-to-end against each committed fixture and asserts
    # the exact, known-good report values. These same expected values are what
    # the act-based pipeline harness verifies, so this is the local mirror of
    # the CI assertions.

    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:Cli      = Join-Path $script:RepoRoot 'Invoke-ArtifactCleanupCli.ps1'
        $script:FixDir   = Join-Path $script:RepoRoot 'fixtures'

        # Pull a "Key: value" line out of a report body.
        function Get-ReportValue {
            param($Report, $Key)
            if ($Report -match "(?m)^\s*$([regex]::Escape($Key)):\s*(.+?)\s*$") { return $Matches[1] }
            return $null
        }
    }

    It 'produces the known-good plan for fixture <Fixture>' -TestCases @(
        @{ Fixture = 'scenario-max-age.json';         Mode = 'DRY-RUN'; Total = '3'; Deleted = '2'; Retained = '1'; Reclaimed = '4194304'; ReclaimedHuman = '4 MB'; RetainedBytes = '2097152' }
        @{ Fixture = 'scenario-keep-latest.json';      Mode = 'DRY-RUN'; Total = '5'; Deleted = '1'; Retained = '4'; Reclaimed = '1048576'; ReclaimedHuman = '1 MB'; RetainedBytes = '3145728' }
        @{ Fixture = 'scenario-combined.json';         Mode = 'DRY-RUN'; Total = '6'; Deleted = '4'; Retained = '2'; Reclaimed = '4194304'; ReclaimedHuman = '4 MB'; RetainedBytes = '2097152' }
        @{ Fixture = 'scenario-execute-warning.json';  Mode = 'EXECUTE'; Total = '2'; Deleted = '2'; Retained = '0'; Reclaimed = '1000';    ReclaimedHuman = '1000 B'; RetainedBytes = '0' }
    ) {
        param($Fixture, $Mode, $Total, $Deleted, $Retained, $Reclaimed, $ReclaimedHuman, $RetainedBytes)

        $path = Join-Path $script:FixDir $Fixture
        $out = & $script:Cli -ScenarioPath $path 2>&1 | Out-String

        $LASTEXITCODE | Should -Be 0
        $out | Should -Match '##CLEANUP-REPORT-BEGIN##'
        $out | Should -Match '##CLEANUP-REPORT-END##'

        (Get-ReportValue $out 'Mode')                | Should -Be $Mode
        (Get-ReportValue $out 'TotalArtifacts')      | Should -Be $Total
        (Get-ReportValue $out 'DeletedCount')        | Should -Be $Deleted
        (Get-ReportValue $out 'RetainedCount')       | Should -Be $Retained
        (Get-ReportValue $out 'SpaceReclaimedBytes') | Should -Be $Reclaimed
        (Get-ReportValue $out 'SpaceReclaimedHuman') | Should -Be $ReclaimedHuman
        (Get-ReportValue $out 'RetainedSizeBytes')   | Should -Be $RetainedBytes
    }

    It 'raises a warning for the execute-warning fixture' {
        $path = Join-Path $script:FixDir 'scenario-execute-warning.json'
        $out = & $script:Cli -ScenarioPath $path 2>&1 | Out-String
        $out | Should -Match 'WARNING:'
    }

    It 'exits non-zero with a clear message when the scenario file is missing' {
        $out = & $script:Cli -ScenarioPath (Join-Path $script:FixDir 'does-not-exist.json') 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'artifact-cleanup failed'
    }
}

Describe 'Format-CleanupReport' {

    BeforeAll {
        $script:RptRefDate = [datetime]'2026-06-28T00:00:00Z'
        $script:RptArtifacts = @(
            [pscustomobject]@{ Name = 'old';    SizeBytes = 1024; CreatedAt = $script:RptRefDate.AddDays(-90); WorkflowRunId = 1 }
            [pscustomobject]@{ Name = 'recent'; SizeBytes = 2048; CreatedAt = $script:RptRefDate.AddDays(-5);  WorkflowRunId = 1 }
        )
    }

    It 'renders parseable summary lines with exact values' {
        $plan   = Invoke-ArtifactCleanup -Artifacts $script:RptArtifacts -MaxAgeDays 30 -DryRun -ReferenceDate $script:RptRefDate
        $report = Format-CleanupReport -Plan $plan

        $report | Should -Match 'TotalArtifacts:\s*2'
        $report | Should -Match 'DeletedCount:\s*1'
        $report | Should -Match 'RetainedCount:\s*1'
        $report | Should -Match 'SpaceReclaimedBytes:\s*1024'
    }

    It 'includes a DRY-RUN banner when the plan is a dry run' {
        $plan   = Invoke-ArtifactCleanup -Artifacts $script:RptArtifacts -MaxAgeDays 30 -DryRun -ReferenceDate $script:RptRefDate
        $report = Format-CleanupReport -Plan $plan
        $report | Should -Match 'DRY-RUN'
    }

    It 'reports execution (not dry run) when -DryRun is omitted' {
        $plan   = Invoke-ArtifactCleanup -Artifacts $script:RptArtifacts -MaxAgeDays 30 -ReferenceDate $script:RptRefDate
        $report = Format-CleanupReport -Plan $plan
        $report | Should -Match 'EXECUTE'
        $report | Should -Not -Match 'DRY-RUN'
    }

    It 'lists each artifact with its decided action' {
        $plan   = Invoke-ArtifactCleanup -Artifacts $script:RptArtifacts -MaxAgeDays 30 -DryRun -ReferenceDate $script:RptRefDate
        $report = Format-CleanupReport -Plan $plan
        $report | Should -Match 'old'
        $report | Should -Match 'recent'
        $report | Should -Match 'DELETE'
        $report | Should -Match 'RETAIN'
    }

    It 'renders a human-readable reclaimed-space figure' {
        $plan   = Invoke-ArtifactCleanup -Artifacts $script:RptArtifacts -MaxAgeDays 30 -DryRun -ReferenceDate $script:RptRefDate
        $report = Format-CleanupReport -Plan $plan
        $report | Should -Match 'SpaceReclaimedHuman:\s*1 KB'
    }
}
