<#
.SYNOPSIS
    Pester tests for the ArtifactCleanup module.

.DESCRIPTION
    These tests were written using red/green TDD: each describe block began as a
    failing test, the minimum module code was added to make it pass, then the
    code was refactored. Tests cover every public function and every retention
    policy, plus error handling and dry-run behaviour.
#>

BeforeAll {
    # Resolve the module path relative to this test file so the suite runs from
    # any working directory (important for `act` / CI containers).
    $modulePath = Join-Path $PSScriptRoot '..' 'src' 'ArtifactCleanup.psm1'
    Import-Module $modulePath -Force

    # A small helper that builds an artifact object the way the module expects.
    # Using a fixed "reference now" keeps age-based tests deterministic.
    $script:RefNow = [datetime]'2026-06-27T00:00:00Z'

    function New-TestArtifact {
        param(
            [string]   $Name,
            [long]     $SizeBytes,
            [datetime] $CreatedAt,
            [string]   $WorkflowName,
            [long]     $WorkflowRunId
        )
        [pscustomobject]@{
            Name          = $Name
            SizeBytes     = $SizeBytes
            CreatedAt     = $CreatedAt
            WorkflowName  = $WorkflowName
            WorkflowRunId = $WorkflowRunId
        }
    }
}

Describe 'Import-ArtifactData' {
    It 'loads artifacts from a JSON file and normalises the fields' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("art_" + [guid]::NewGuid().ToString('N') + '.json')
        $json = @'
[
  { "name": "build-1", "sizeBytes": 1000, "createdAt": "2026-06-01T00:00:00Z", "workflowName": "ci", "workflowRunId": 101 }
]
'@
        Set-Content -LiteralPath $tmp -Value $json -Encoding utf8
        try {
            $artifacts = Import-ArtifactData -Path $tmp
            $artifacts | Should -HaveCount 1
            $artifacts[0].Name | Should -Be 'build-1'
            $artifacts[0].SizeBytes | Should -Be 1000
            $artifacts[0].WorkflowName | Should -Be 'ci'
            $artifacts[0].WorkflowRunId | Should -Be 101
            $artifacts[0].CreatedAt | Should -BeOfType [datetime]
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-ArtifactData -Path '/no/such/file.json' } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error when the JSON is malformed' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bad_" + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $tmp -Value '{ this is not json' -Encoding utf8
        try {
            { Import-ArtifactData -Path $tmp } | Should -Throw -ExpectedMessage '*Failed to parse*'
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-ArtifactRetentionPlan - no policies' {
    It 'keeps every artifact when no policy is supplied' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -SizeBytes 100 -CreatedAt $RefNow.AddDays(-1) -WorkflowName 'ci' -WorkflowRunId 1
            New-TestArtifact -Name 'b' -SizeBytes 200 -CreatedAt $RefNow.AddDays(-2) -WorkflowName 'ci' -WorkflowRunId 2
        )
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -ReferenceTime $RefNow
        $plan.Summary.DeletedCount   | Should -Be 0
        $plan.Summary.RetainedCount  | Should -Be 2
        $plan.Summary.SpaceReclaimed | Should -Be 0
        ($plan.Items | Where-Object Action -eq 'Keep') | Should -HaveCount 2
    }
}

Describe 'Get-ArtifactRetentionPlan - MaxAgeDays policy' {
    It 'marks artifacts older than the cutoff for deletion' {
        $artifacts = @(
            New-TestArtifact -Name 'fresh' -SizeBytes 100 -CreatedAt $RefNow.AddDays(-5)  -WorkflowName 'ci' -WorkflowRunId 1
            New-TestArtifact -Name 'stale' -SizeBytes 300 -CreatedAt $RefNow.AddDays(-40) -WorkflowName 'ci' -WorkflowRunId 2
        )
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceTime $RefNow

        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.SpaceReclaimed | Should -Be 300
        $deleted = $plan.Items | Where-Object Action -eq 'Delete'
        $deleted.Name   | Should -Be 'stale'
        $deleted.Reason | Should -BeLike '*max age*'
    }

    It 'treats an artifact exactly at the cutoff age as retained (boundary)' {
        $artifacts = @(
            New-TestArtifact -Name 'edge' -SizeBytes 100 -CreatedAt $RefNow.AddDays(-30) -WorkflowName 'ci' -WorkflowRunId 1
        )
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceTime $RefNow
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Get-ArtifactRetentionPlan - KeepLatestPerWorkflow policy' {
    It 'keeps only the N newest artifacts per workflow group' {
        $artifacts = @(
            New-TestArtifact -Name 'ci-old'   -SizeBytes 100 -CreatedAt $RefNow.AddDays(-10) -WorkflowName 'ci'    -WorkflowRunId 1
            New-TestArtifact -Name 'ci-mid'   -SizeBytes 100 -CreatedAt $RefNow.AddDays(-5)  -WorkflowName 'ci'    -WorkflowRunId 2
            New-TestArtifact -Name 'ci-new'   -SizeBytes 100 -CreatedAt $RefNow.AddDays(-1)  -WorkflowName 'ci'    -WorkflowRunId 3
            New-TestArtifact -Name 'rel-only' -SizeBytes 100 -CreatedAt $RefNow.AddDays(-3)  -WorkflowName 'release' -WorkflowRunId 4
        )
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -KeepLatestPerWorkflow 2 -ReferenceTime $RefNow

        # ci keeps the 2 newest (ci-new, ci-mid), deletes ci-old. release keeps its 1.
        $plan.Summary.DeletedCount | Should -Be 1
        $deleted = $plan.Items | Where-Object Action -eq 'Delete'
        $deleted.Name   | Should -Be 'ci-old'
        $deleted.Reason | Should -BeLike '*keep-latest*'
    }
}

Describe 'Get-ArtifactRetentionPlan - MaxTotalSizeBytes policy' {
    It 'deletes oldest-first until the retained total is within the size budget' {
        $artifacts = @(
            New-TestArtifact -Name 'a' -SizeBytes 500 -CreatedAt $RefNow.AddDays(-1) -WorkflowName 'ci' -WorkflowRunId 1
            New-TestArtifact -Name 'b' -SizeBytes 500 -CreatedAt $RefNow.AddDays(-2) -WorkflowName 'ci' -WorkflowRunId 2
            New-TestArtifact -Name 'c' -SizeBytes 500 -CreatedAt $RefNow.AddDays(-3) -WorkflowName 'ci' -WorkflowRunId 3
        )
        # Budget 1000 -> must drop 500 worth. Oldest (c) goes first.
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxTotalSizeBytes 1000 -ReferenceTime $RefNow

        $plan.Summary.DeletedCount   | Should -Be 1
        $plan.Summary.RetainedSize   | Should -Be 1000
        $deleted = $plan.Items | Where-Object Action -eq 'Delete'
        $deleted.Name   | Should -Be 'c'
        $deleted.Reason | Should -BeLike '*max total size*'
    }
}

Describe 'Get-ArtifactRetentionPlan - combined policies' {
    It 'applies age, keep-latest, then size in order and reports a coherent summary' {
        $artifacts = @(
            New-TestArtifact -Name 'ancient' -SizeBytes 100 -CreatedAt $RefNow.AddDays(-90) -WorkflowName 'ci' -WorkflowRunId 1
            New-TestArtifact -Name 'old'     -SizeBytes 800 -CreatedAt $RefNow.AddDays(-10) -WorkflowName 'ci' -WorkflowRunId 2
            New-TestArtifact -Name 'mid'     -SizeBytes 800 -CreatedAt $RefNow.AddDays(-5)  -WorkflowName 'ci' -WorkflowRunId 3
            New-TestArtifact -Name 'new'     -SizeBytes 800 -CreatedAt $RefNow.AddDays(-1)  -WorkflowName 'ci' -WorkflowRunId 4
        )
        # MaxAge 30 deletes 'ancient'. KeepLatest 3 keeps old/mid/new (still 3). Size 1600
        # forces dropping 'old' (oldest remaining). Retained: mid+new = 1600.
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 3 -MaxTotalSizeBytes 1600 -ReferenceTime $RefNow

        $plan.Summary.DeletedCount   | Should -Be 2
        $plan.Summary.RetainedCount  | Should -Be 2
        $plan.Summary.RetainedSize   | Should -Be 1600
        $plan.Summary.SpaceReclaimed | Should -Be 900
        ($plan.Items | Where-Object Action -eq 'Delete').Name | Should -Be @('ancient', 'old')
    }
}

Describe 'Invoke-ArtifactCleanup - dry-run vs execute' {
    BeforeEach {
        $script:fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("fx_" + [guid]::NewGuid().ToString('N') + '.json')
        $data = @'
[
  { "name": "old",  "sizeBytes": 300, "createdAt": "2026-04-01T00:00:00Z", "workflowName": "ci", "workflowRunId": 1 },
  { "name": "new",  "sizeBytes": 100, "createdAt": "2026-06-26T00:00:00Z", "workflowName": "ci", "workflowRunId": 2 }
]
'@
        Set-Content -LiteralPath $script:fixture -Value $data -Encoding utf8
    }
    AfterEach {
        Remove-Item -LiteralPath $script:fixture -ErrorAction SilentlyContinue
    }

    It 'in dry-run reports the plan and marks the run as DryRun without executing' {
        $result = Invoke-ArtifactCleanup -Path $script:fixture -MaxAgeDays 30 -DryRun -ReferenceTime $RefNow
        $result.DryRun | Should -BeTrue
        $result.Summary.DeletedCount | Should -Be 1
        ($result.Items | Where-Object Action -eq 'Delete').Executed | Should -BeFalse
    }

    It 'in execute mode marks deleted artifacts as Executed via the deletion callback' {
        $script:invoked = New-Object System.Collections.Generic.List[string]
        $deleter = { param($artifact) $script:invoked.Add($artifact.Name) }

        $result = Invoke-ArtifactCleanup -Path $script:fixture -MaxAgeDays 30 -DeleteAction $deleter -ReferenceTime $RefNow
        $result.DryRun | Should -BeFalse
        $script:invoked | Should -Contain 'old'
        $script:invoked | Should -Not -Contain 'new'
        ($result.Items | Where-Object Action -eq 'Delete').Executed | Should -BeTrue
    }
}

Describe 'Format-CleanupSummary' {
    It 'produces a human-readable report containing the headline numbers' {
        $artifacts = @(
            New-TestArtifact -Name 'old' -SizeBytes 1048576 -CreatedAt $RefNow.AddDays(-40) -WorkflowName 'ci' -WorkflowRunId 1
            New-TestArtifact -Name 'new' -SizeBytes 1048576 -CreatedAt $RefNow.AddDays(-1)  -WorkflowName 'ci' -WorkflowRunId 2
        )
        $plan = Get-ArtifactRetentionPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceTime $RefNow
        $text = Format-CleanupSummary -Plan $plan

        $text | Should -BeLike '*Artifacts deleted: 1*'
        $text | Should -BeLike '*Artifacts retained: 1*'
        $text | Should -BeLike '*Space reclaimed:*'
    }
}

Describe 'Get-ArtifactRetentionPlan - input validation' {
    It 'throws when MaxAgeDays is negative' {
        { Get-ArtifactRetentionPlan -Artifacts @() -MaxAgeDays -1 -ReferenceTime $RefNow } |
            Should -Throw -ExpectedMessage '*MaxAgeDays*'
    }

    It 'accepts an empty artifact set and returns a zeroed summary' {
        $plan = Get-ArtifactRetentionPlan -Artifacts @() -ReferenceTime $RefNow
        $plan.Summary.DeletedCount  | Should -Be 0
        $plan.Summary.RetainedCount | Should -Be 0
    }
}
