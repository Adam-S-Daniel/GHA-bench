#requires -Modules Pester

# Pester tests for the Artifact Cleanup script.
#
# We follow red/green TDD: each Describe block was written before the
# corresponding function existed, then the script was implemented to satisfy it.
#
# The suite has three layers:
#   1. Unit tests for the pure policy/plan logic (fast, dot-source the script).
#   2. Workflow-structure tests (YAML shape, script references, actionlint).
#   3. An end-to-end test that runs the real workflow through `act` in Docker
#      and asserts on EXACT expected values per fixture.

BeforeAll {
    # Dot-source the script under test. Its CLI/"main" block is guarded so it
    # only runs when -InputPath is supplied; dot-sourcing just imports functions.
    . "$PSScriptRoot/ArtifactCleanup.ps1"

    $script:Root        = $PSScriptRoot
    $script:Workflow    = Join-Path $PSScriptRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:FixtureDir  = Join-Path $PSScriptRoot 'fixtures'

    # Helper to build artifacts tersely in unit tests.
    function New-TestArtifact {
        param([string]$Name, [long]$Size, [string]$Created, [int]$RunId = 0)
        [pscustomobject]@{
            Name = $Name; Size = $Size; Created = [datetime]$Created; WorkflowRunId = $RunId
        }
    }
}

# ---------------------------------------------------------------------------
# Layer 1: unit tests
# ---------------------------------------------------------------------------

Describe 'Get-ArtifactCleanupPlan - MaxAgeDays policy' {
    It 'marks artifacts older than MaxAgeDays for deletion' {
        $ref = [datetime]'2026-06-01T00:00:00Z'
        $artifacts = @(
            New-TestArtifact 'build' 100 '2026-05-20' 1
            New-TestArtifact 'build' 200 '2026-04-01' 2
            New-TestArtifact 'test'  300 '2026-03-01' 3
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate $ref

        $plan.Summary.DeletedCount        | Should -Be 2
        $plan.Summary.RetainedCount       | Should -Be 1
        $plan.Summary.SpaceReclaimedBytes | Should -Be 500
        $plan.Summary.RetainedSizeBytes   | Should -Be 100
        ($plan.Delete | ForEach-Object { $_.Reasons }) | Should -Contain 'MaxAge'
    }

    It 'retains everything when MaxAgeDays is 0 (disabled)' {
        $artifacts = @(New-TestArtifact 'a' 1 '2000-01-01' 1)
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 0 -ReferenceDate ([datetime]'2026-06-01')
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Get-ArtifactCleanupPlan - KeepLatestN policy' {
    It 'keeps only the N newest artifacts per group (by Name)' {
        $artifacts = @(
            New-TestArtifact 'build' 10 '2026-06-01' 1
            New-TestArtifact 'build' 20 '2026-05-01' 2
            New-TestArtifact 'build' 30 '2026-04-01' 3
            New-TestArtifact 'build' 40 '2026-03-01' 4
            New-TestArtifact 'test'  5  '2026-06-01' 5
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -KeepLatestN 2

        $plan.Summary.DeletedCount        | Should -Be 2
        $plan.Summary.RetainedCount       | Should -Be 3
        $plan.Summary.SpaceReclaimedBytes | Should -Be 70   # 30 + 40 (oldest builds)
        # The retained build artifacts must be the two newest.
        $retainedBuild = $plan.Retain | Where-Object Name -eq 'build' | Sort-Object Created
        $retainedBuild.Size | Should -Be @(20, 10)
    }
}

Describe 'Get-ArtifactCleanupPlan - MaxTotalSizeBytes policy' {
    It 'deletes oldest artifacts until under the size cap' {
        $artifacts = @(
            New-TestArtifact 'bundle' 600 '2026-06-01' 1
            New-TestArtifact 'bundle' 500 '2026-05-01' 2
            New-TestArtifact 'bundle' 400 '2026-04-01' 3
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 1000

        # 1500 total -> delete 400 (1100) then 500 (600) -> retained 600 <= 1000
        $plan.Summary.DeletedCount        | Should -Be 2
        $plan.Summary.RetainedSizeBytes   | Should -Be 600
        $plan.Summary.SpaceReclaimedBytes | Should -Be 900
    }

    It 'does nothing when already under the cap' {
        $artifacts = @(New-TestArtifact 'x' 100 '2026-06-01' 1)
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxTotalSizeBytes 1000
        $plan.Summary.DeletedCount | Should -Be 0
    }
}

Describe 'Get-ArtifactCleanupPlan - combined policies and dry-run' {
    It 'applies age, keep-latest, then size cap and flags dry-run' {
        $ref = [datetime]'2026-06-01T00:00:00Z'
        $artifacts = @(
            New-TestArtifact 'build' 100 '2026-05-25' 1
            New-TestArtifact 'build' 100 '2026-05-20' 2
            New-TestArtifact 'build' 100 '2026-05-15' 3
            New-TestArtifact 'build' 100 '2026-01-01' 4
            New-TestArtifact 'test'  100 '2026-05-30' 5
        )

        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -ReferenceDate $ref `
            -MaxAgeDays 60 -KeepLatestN 2 -MaxTotalSizeBytes 250 -DryRun

        $plan.DryRun                       | Should -BeTrue
        $plan.Summary.DeletedCount         | Should -Be 3
        $plan.Summary.RetainedCount        | Should -Be 2
        $plan.Summary.SpaceReclaimedBytes  | Should -Be 300
        $plan.Summary.RetainedSizeBytes    | Should -Be 200
    }
}

Describe 'Get-ArtifactCleanupPlan - validation and edge cases' {
    It 'throws on negative policy values' {
        { Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays -1 } | Should -Throw '*MaxAgeDays*'
    }

    It 'handles an empty artifact list gracefully' {
        $plan = Get-ArtifactCleanupPlan -Artifacts @() -MaxAgeDays 30
        $plan.Summary.TotalArtifacts | Should -Be 0
        $plan.Summary.DeletedCount   | Should -Be 0
    }
}

Describe 'ConvertTo-Artifact - input normalisation' {
    It 'throws a meaningful error when a required field is missing' {
        { [pscustomobject]@{ Name = 'x'; Size = 1 } | ConvertTo-Artifact } |
            Should -Throw "*missing required property 'Created'*"
    }

    It 'throws on an unparseable date' {
        { [pscustomobject]@{ Name = 'x'; Size = 1; Created = 'not-a-date' } | ConvertTo-Artifact } |
            Should -Throw '*unparseable Created date*'
    }
}

Describe 'Import-ArtifactConfig + Get-ArtifactCleanupPlan over fixtures' {
    It 'reproduces the known-good summary for <Fixture>' -ForEach @(
        @{ Fixture = 'max-age';         Deleted = 2; Retained = 1; Reclaimed = 500; RetainedSize = 100; DryRun = $false }
        @{ Fixture = 'keep-latest';     Deleted = 2; Retained = 3; Reclaimed = 70;  RetainedSize = 35;  DryRun = $false }
        @{ Fixture = 'max-size';        Deleted = 2; Retained = 1; Reclaimed = 900; RetainedSize = 600; DryRun = $false }
        @{ Fixture = 'combined-dryrun'; Deleted = 3; Retained = 2; Reclaimed = 300; RetainedSize = 200; DryRun = $true  }
    ) {
        $cfg = Import-ArtifactConfig -Path (Join-Path $FixtureDir "$Fixture.json")
        $planArgs = @{ Artifacts = $cfg.Artifacts }
        foreach ($k in 'MaxAgeDays', 'MaxTotalSizeBytes', 'KeepLatestN', 'GroupBy', 'ReferenceDate') {
            if ($cfg.ContainsKey($k)) { $planArgs[$k] = $cfg[$k] }
        }
        if ($cfg.ContainsKey('DryRun') -and $cfg.DryRun) { $planArgs.DryRun = $true }

        $plan = Get-ArtifactCleanupPlan @planArgs

        $plan.Summary.DeletedCount        | Should -Be $Deleted
        $plan.Summary.RetainedCount       | Should -Be $Retained
        $plan.Summary.SpaceReclaimedBytes | Should -Be $Reclaimed
        $plan.Summary.RetainedSizeBytes   | Should -Be $RetainedSize
        $plan.DryRun                      | Should -Be $DryRun
    }

    It 'throws when the input file does not exist' {
        { Import-ArtifactConfig -Path (Join-Path $FixtureDir 'nope.json') } | Should -Throw '*not found*'
    }
}

Describe 'Format-ArtifactCleanupReport' {
    It 'emits a stable SUMMARY line with exact values' {
        $artifacts = @(New-TestArtifact 'build' 200 '2026-04-01' 1)
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate ([datetime]'2026-06-01')
        $text = Format-ArtifactCleanupReport -Plan $plan -Case 'demo' -Format Text
        $text | Should -Match 'SUMMARY: case=demo total=1 retained=0 deleted=1 reclaimed=200 retainedSize=0 dryRun=false'
    }

    It 'produces valid JSON when -Format Json' {
        $artifacts = @(New-TestArtifact 'build' 200 '2026-04-01' 1)
        $plan = Get-ArtifactCleanupPlan -Artifacts $artifacts -MaxAgeDays 30 -ReferenceDate ([datetime]'2026-06-01')
        $json = Format-ArtifactCleanupReport -Plan $plan -Format Json
        { $json | ConvertFrom-Json } | Should -Not -Throw
        ($json | ConvertFrom-Json).Summary.DeletedCount | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
# Layer 2: workflow structure tests
# ---------------------------------------------------------------------------

Describe 'Workflow file structure' {
    BeforeAll {
        $script:wf = Get-Content -LiteralPath $script:Workflow -Raw
    }

    It 'exists' {
        Test-Path -LiteralPath $script:Workflow | Should -BeTrue
    }

    It 'declares the expected triggers' {
        $script:wf | Should -Match '(?m)^on:'
        $script:wf | Should -Match 'push:'
        $script:wf | Should -Match 'pull_request:'
        $script:wf | Should -Match 'schedule:'
        $script:wf | Should -Match 'workflow_dispatch:'
    }

    It 'declares permissions and jobs with a dependency' {
        $script:wf | Should -Match '(?m)^permissions:'
        $script:wf | Should -Match '(?m)^\s*cleanup:'
        $script:wf | Should -Match '(?m)^\s*report:'
        $script:wf | Should -Match 'needs:\s*cleanup'
    }

    It 'references the script and uses shell: pwsh' {
        $script:wf | Should -Match 'ArtifactCleanup\.ps1'
        $script:wf | Should -Match 'shell:\s*pwsh'
        $script:wf | Should -Match 'actions/checkout@v4'
    }

    It 'references script and fixture paths that actually exist' {
        Test-Path -LiteralPath (Join-Path $script:Root 'ArtifactCleanup.ps1') | Should -BeTrue
        foreach ($fx in 'max-age', 'keep-latest', 'max-size', 'combined-dryrun') {
            Test-Path -LiteralPath (Join-Path $script:FixtureDir "$fx.json") | Should -BeTrue
        }
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $actionlint = Get-Command actionlint -ErrorAction SilentlyContinue
        if (-not $actionlint) { Set-ItResult -Skipped -Because 'actionlint not installed'; return }

        $out = & actionlint $script:Workflow 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
    }
}

# ---------------------------------------------------------------------------
# Layer 3: end-to-end execution through act (Docker)
# ---------------------------------------------------------------------------
#
# The workflow runs all four fixtures via a job matrix in a SINGLE `act push`
# invocation. We capture the full output to act-result.txt and assert on the
# exact SUMMARY line for every fixture plus "Job succeeded" markers.

Describe 'Workflow runs end-to-end via act' -Tag 'Act' {
    BeforeAll {
        $script:actResult = Join-Path $script:Root 'act-result.txt'

        $script:expected = @(
            'SUMMARY: case=max-age total=3 retained=1 deleted=2 reclaimed=500 retainedSize=100 dryRun=false'
            'SUMMARY: case=keep-latest total=5 retained=3 deleted=2 reclaimed=70 retainedSize=35 dryRun=false'
            'SUMMARY: case=max-size total=3 retained=1 deleted=2 reclaimed=900 retainedSize=600 dryRun=false'
            'SUMMARY: case=combined-dryrun total=5 retained=2 deleted=3 reclaimed=300 retainedSize=200 dryRun=true'
        )

        $act = Get-Command act -ErrorAction SilentlyContinue
        $script:actAvailable = [bool]$act

        if ($script:actAvailable) {
            # Build an isolated temp git repo containing only the project files.
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-cleanup-act-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null

            Copy-Item -Path (Join-Path $script:Root 'ArtifactCleanup.ps1') -Destination $tmp
            Copy-Item -Path (Join-Path $script:Root 'fixtures') -Destination $tmp -Recurse
            New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
            Copy-Item -Path $script:Workflow -Destination (Join-Path $tmp '.github/workflows')
            if (Test-Path (Join-Path $script:Root '.actrc')) {
                Copy-Item -Path (Join-Path $script:Root '.actrc') -Destination $tmp
            }

            Push-Location $tmp
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'test@example.com' 2>&1 | Out-Null
                git config user.name 'test' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m 'test' 2>&1 | Out-Null

                # Single act run executes the whole matrix.
                # --pull=false: the act image is present locally only; without
                # this act force-pulls it and fails registry authentication.
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $script:actExit = $LASTEXITCODE
            } finally {
                Pop-Location
            }

            $header = "===== act push (all fixtures via matrix) exit=$script:actExit ====="
            Set-Content -LiteralPath $script:actResult -Value ($header + [Environment]::NewLine + $output) -Encoding utf8

            $script:actOutput = $output
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    It 'has act available' {
        if (-not $script:actAvailable) { Set-ItResult -Skipped -Because 'act not installed'; return }
        $script:actAvailable | Should -BeTrue
    }

    It 'exits with code 0' {
        if (-not $script:actAvailable) { Set-ItResult -Skipped -Because 'act not installed'; return }
        $script:actExit | Should -Be 0 -Because $script:actOutput
    }

    It 'writes act-result.txt' {
        if (-not $script:actAvailable) { Set-ItResult -Skipped -Because 'act not installed'; return }
        Test-Path -LiteralPath $script:actResult | Should -BeTrue
    }

    It 'contains the exact SUMMARY line for <_>' -ForEach @(
        'max-age', 'keep-latest', 'max-size', 'combined-dryrun'
    ) {
        if (-not $script:actAvailable) { Set-ItResult -Skipped -Because 'act not installed'; return }
        $fixture = $_
        # Pick the known-good SUMMARY line for this fixture and require it verbatim.
        $wanted = $script:expected | Where-Object { $_ -like "*case=$fixture *" }
        $wanted | Should -Not -BeNullOrEmpty
        $script:actOutput | Should -BeLike "*$wanted*" -Because $script:actOutput
    }

    It 'shows every job succeeded (5 jobs: 4 matrix + report)' {
        if (-not $script:actAvailable) { Set-ItResult -Skipped -Because 'act not installed'; return }
        $succeeded = ([regex]::Matches($script:actOutput, 'Job succeeded')).Count
        $succeeded | Should -BeGreaterOrEqual 5 -Because $script:actOutput
    }
}
