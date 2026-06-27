#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester unit tests for the artifact cleanup module.
# Developed red/green/refactor: every Describe block below was first written as
# a failing assertion, then the minimum module code was added to satisfy it.

BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    Import-Module (Join-Path $here 'ArtifactCleanup.psm1') -Force

    # A fixed "now" so age-based assertions are deterministic.
    $script:Now = [datetime]::new(2026, 6, 27, 0, 0, 0, [System.DateTimeKind]::Utc)

    # Helper: build an artifact created $DaysAgo days before the reference date.
    function New-TestArtifact {
        param(
            [string] $Name,
            [long]   $Size,
            [int]    $DaysAgo,
            [string] $RunId
        )
        [PSCustomObject]@{
            Name          = $Name
            Size          = $Size
            CreatedAt     = $script:Now.AddDays(-$DaysAgo)
            WorkflowRunId = $RunId
        }
    }
}

Describe 'Get-ArtifactDeletionPlan : function surface' {
    It 'is exported and callable' {
        Get-Command Get-ArtifactDeletionPlan -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'returns a plan with Decisions and Summary on empty input' {
        $plan = Get-ArtifactDeletionPlan -Artifacts @()
        $plan.PSObject.Properties.Name | Should -Contain 'Decisions'
        $plan.PSObject.Properties.Name | Should -Contain 'Summary'
        $plan.Summary.TotalArtifacts | Should -Be 0
        $plan.Summary.SpaceReclaimed | Should -Be 0
    }
}

Describe 'Input validation (ConvertTo-ArtifactObject)' {
    It 'throws when Name is missing' {
        { Get-ArtifactDeletionPlan -Artifacts @(@{ Size = 1; CreatedAt = $script:Now; WorkflowRunId = 'r' }) } |
            Should -Throw -ExpectedMessage "*missing a required 'Name'*"
    }
    It 'throws when Size is missing' {
        { Get-ArtifactDeletionPlan -Artifacts @(@{ Name = 'a'; CreatedAt = $script:Now; WorkflowRunId = 'r' }) } |
            Should -Throw -ExpectedMessage "*missing a required 'Size'*"
    }
    It 'throws on a negative Size' {
        { Get-ArtifactDeletionPlan -Artifacts @(@{ Name = 'a'; Size = -5; CreatedAt = $script:Now; WorkflowRunId = 'r' }) } |
            Should -Throw -ExpectedMessage "*negative Size*"
    }
    It 'throws on an unparseable CreatedAt' {
        { Get-ArtifactDeletionPlan -Artifacts @(@{ Name = 'a'; Size = 1; CreatedAt = 'not-a-date'; WorkflowRunId = 'r' }) } |
            Should -Throw -ExpectedMessage "*unparseable CreatedAt*"
    }
    It 'throws when WorkflowRunId is missing' {
        { Get-ArtifactDeletionPlan -Artifacts @(@{ Name = 'a'; Size = 1; CreatedAt = $script:Now }) } |
            Should -Throw -ExpectedMessage "*missing a required 'WorkflowRunId'*"
    }
    It 'parses ISO-8601 string dates' {
        $plan = Get-ArtifactDeletionPlan -Artifacts @(
            @{ Name = 'a'; Size = 1; CreatedAt = '2026-01-01T00:00:00Z'; WorkflowRunId = 'r' }
        ) -MaxAgeDays 30 -ReferenceDate $script:Now
        # Jan 1 is far older than 30 days before Jun 27 -> deleted.
        $plan.Summary.DeletedCount | Should -Be 1
    }
}

Describe 'Policy: MaxAgeDays' {
    BeforeEach {
        $script:artifacts = @(
            (New-TestArtifact -Name 'fresh'   -Size 100 -DaysAgo 1  -RunId 'r1'),
            (New-TestArtifact -Name 'edge'    -Size 100 -DaysAgo 30 -RunId 'r1'),
            (New-TestArtifact -Name 'old'     -Size 100 -DaysAgo 31 -RunId 'r1'),
            (New-TestArtifact -Name 'ancient' -Size 100 -DaysAgo 90 -RunId 'r1')
        )
    }
    It 'deletes only artifacts strictly older than the cutoff' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -MaxAgeDays 30 -ReferenceDate $script:Now
        ($plan.Decisions | Where-Object Action -EQ 'Delete').Name | Should -Be @('old', 'ancient')
        $plan.Summary.DeletedCount | Should -Be 2
        $plan.Summary.SpaceReclaimed | Should -Be 200
    }
    It 'keeps an artifact exactly at the cutoff boundary' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -MaxAgeDays 30 -ReferenceDate $script:Now
        ($plan.Decisions | Where-Object Name -EQ 'edge').Action | Should -Be 'Retain'
    }
    It 'does nothing when the policy is disabled (0)' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -ReferenceDate $script:Now
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Policy: KeepLatestPerWorkflow' {
    BeforeEach {
        # r1 has 3 artifacts; r2 has 2. Keep latest 1 per run.
        $script:artifacts = @(
            (New-TestArtifact -Name 'r1-new' -Size 10 -DaysAgo 1 -RunId 'r1'),
            (New-TestArtifact -Name 'r1-mid' -Size 10 -DaysAgo 5 -RunId 'r1'),
            (New-TestArtifact -Name 'r1-old' -Size 10 -DaysAgo 9 -RunId 'r1'),
            (New-TestArtifact -Name 'r2-new' -Size 10 -DaysAgo 2 -RunId 'r2'),
            (New-TestArtifact -Name 'r2-old' -Size 10 -DaysAgo 8 -RunId 'r2')
        )
    }
    It 'keeps the N newest per workflow run and deletes the rest' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -KeepLatestPerWorkflow 1 -ReferenceDate $script:Now
        ($plan.Decisions | Where-Object Action -EQ 'Retain').Name | Should -Be @('r1-new', 'r2-new')
        $plan.Summary.DeletedCount | Should -Be 3
    }
    It 'retains everything when N >= group size' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -KeepLatestPerWorkflow 5 -ReferenceDate $script:Now
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Policy: MaxTotalSize' {
    BeforeEach {
        # Total = 600. Oldest-first deletion order: old(100s)..new.
        $script:artifacts = @(
            (New-TestArtifact -Name 'a-newest' -Size 100 -DaysAgo 1 -RunId 'r1'),
            (New-TestArtifact -Name 'b'        -Size 200 -DaysAgo 2 -RunId 'r1'),
            (New-TestArtifact -Name 'c'        -Size 150 -DaysAgo 3 -RunId 'r2'),
            (New-TestArtifact -Name 'd-oldest' -Size 150 -DaysAgo 4 -RunId 'r2')
        )
    }
    It 'deletes oldest-first until total fits under the cap' {
        # Cap 350: delete d-oldest(150)->450, then c(150)->300 <= 350. Stop.
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -MaxTotalSize 350 -ReferenceDate $script:Now
        ($plan.Decisions | Where-Object Action -EQ 'Delete').Name | Should -Be @('c', 'd-oldest')
        $plan.Summary.RetainedSize | Should -Be 300
        $plan.Summary.SpaceReclaimed | Should -Be 300
    }
    It 'deletes nothing when already under the cap' {
        $plan = Get-ArtifactDeletionPlan -Artifacts $script:artifacts -MaxTotalSize 600 -ReferenceDate $script:Now
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Combined policies' {
    It 'applies age + keep-latest + size cap together with accumulating reasons' {
        $artifacts = @(
            (New-TestArtifact -Name 'r1-new'   -Size 500 -DaysAgo 1   -RunId 'r1'),
            (New-TestArtifact -Name 'r1-old'   -Size 100 -DaysAgo 100 -RunId 'r1'),
            (New-TestArtifact -Name 'r2-new'   -Size 100 -DaysAgo 2   -RunId 'r2'),
            (New-TestArtifact -Name 'r2-mid'   -Size 100 -DaysAgo 3   -RunId 'r2')
        )
        # Age 30: r1-old(100d) -> deleted [max-age].
        # KeepLatest 1: per r2, keep r2-new, delete r2-mid [keep-latest];
        #               per r1, r1-old already flagged, keep r1-new.
        # Survivors so far: r1-new(500), r2-new(100) = 600.
        # MaxTotalSize 550: delete oldest survivor first -> r2-new(100) -> 500 <= 550.
        $plan = Get-ArtifactDeletionPlan -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -MaxTotalSize 550 -ReferenceDate $script:Now

        ($plan.Decisions | Where-Object Action -EQ 'Retain').Name | Should -Be @('r1-new')
        $plan.Summary.DeletedCount  | Should -Be 3
        $plan.Summary.RetainedSize  | Should -Be 500
        $plan.Summary.SpaceReclaimed | Should -Be 300

        $r2mid = $plan.Decisions | Where-Object Name -EQ 'r2-mid'
        $r2mid.Reasons | Should -Contain 'keep-latest'
        $r1old = $plan.Decisions | Where-Object Name -EQ 'r1-old'
        $r1old.Reasons | Should -Contain 'max-age'
    }
}

Describe 'Dry-run behaviour (Invoke-ArtifactCleanup)' {
    BeforeEach {
        $script:artifacts = @(
            (New-TestArtifact -Name 'old' -Size 100 -DaysAgo 90 -RunId 'r1'),
            (New-TestArtifact -Name 'new' -Size 100 -DaysAgo 1  -RunId 'r1')
        )
    }
    It 'records DryRun=true and never invokes the delete action' {
        $script:deleted = @()
        $plan = Invoke-ArtifactCleanup -Artifacts $script:artifacts -MaxAgeDays 30 `
            -ReferenceDate $script:Now -DryRun `
            -DeleteAction { param($d) $script:deleted += $d.Name }
        $plan.Summary.DryRun | Should -BeTrue
        $plan.Summary.DeletedCount | Should -Be 1   # plan still identifies it
        $script:deleted | Should -BeNullOrEmpty      # but no action ran
    }
    It 'invokes the delete action for each deleted artifact in live mode' {
        $script:deleted = @()
        $null = Invoke-ArtifactCleanup -Artifacts $script:artifacts -MaxAgeDays 30 `
            -ReferenceDate $script:Now `
            -DeleteAction { param($d) $script:deleted += $d.Name }
        $script:deleted | Should -Be @('old')
    }
    It 'surfaces a meaningful error when the delete action fails' {
        { Invoke-ArtifactCleanup -Artifacts $script:artifacts -MaxAgeDays 30 `
            -ReferenceDate $script:Now `
            -DeleteAction { throw 'api down' } } |
            Should -Throw -ExpectedMessage "*Failed to delete artifact 'old'*api down*"
    }
}

Describe 'Format-DeletionPlanSummary' {
    It 'emits exact machine-parseable RESULT_ lines' {
        $artifacts = @(
            (New-TestArtifact -Name 'old' -Size 100 -DaysAgo 90 -RunId 'r1'),
            (New-TestArtifact -Name 'new' -Size 250 -DaysAgo 1  -RunId 'r1')
        )
        $text = Get-ArtifactDeletionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $script:Now |
            Format-DeletionPlanSummary
        $text | Should -Match 'RESULT_TOTAL=2'
        $text | Should -Match 'RESULT_RETAINED=1'
        $text | Should -Match 'RESULT_DELETED=1'
        $text | Should -Match 'RESULT_RECLAIMED=100'
        $text | Should -Match 'RESULT_RETAINED_SIZE=250'
        $text | Should -Match 'RESULT_DRYRUN=false'
    }
}

Describe 'Import-ArtifactFixture' {
    It 'throws a clear error for a missing file' {
        { Import-ArtifactFixture -Path (Join-Path $TestDrive 'nope.json') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
    It 'loads and normalises a JSON array of artifacts' {
        $file = Join-Path $TestDrive 'arts.json'
        @(
            @{ Name = 'a'; Size = 10; CreatedAt = '2026-06-01T00:00:00Z'; WorkflowRunId = 'r1' },
            @{ Name = 'b'; Size = 20; CreatedAt = '2026-06-02T00:00:00Z'; WorkflowRunId = 'r2' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $file
        $arts = Import-ArtifactFixture -Path $file
        $arts.Count | Should -Be 2
        $arts[0].Size | Should -BeOfType [long]
        ($arts | Where-Object Name -EQ 'b').WorkflowRunId | Should -Be 'r2'
    }
    It 'throws a clear error for malformed JSON' {
        $file = Join-Path $TestDrive 'bad.json'
        'this is { not json' | Set-Content -LiteralPath $file
        { Import-ArtifactFixture -Path $file } | Should -Throw -ExpectedMessage '*Failed to parse JSON*'
    }
}
