# Tests for the CLI entry point Invoke-ArtifactCleanup.ps1.
# Written first (red) in TDD cycle 5, before the script existed.
#
# Expected numbers for the sample fixture with MaxAgeDays=30,
# KeepLatestPerWorkflow=1, MaxTotalSizeBytes=157286400 (150 MB),
# ReferenceDate=2026-07-01:
#   - build-logs-run1001 (50 MB) deleted by MaxAge (unprotected, 77 days old)
#   - build-logs-run1002 (80 MB) deleted by MaxTotalSize (oldest unprotected
#     survivor; retained set 210 MB > 150 MB budget)
#   - 3 artifacts retained (130 MB), 130 MB reclaimed.

BeforeAll {
    $script:ScriptPath  = Join-Path $PSScriptRoot '..' 'Invoke-ArtifactCleanup.ps1'
    $script:FixturePath = Join-Path $PSScriptRoot 'fixtures' 'sample-artifacts.json'

    function Invoke-Cli {
        param([switch]$DryRun, [string]$PlanPath)
        # Run in-process via & so tests stay fast; capture all output lines.
        $extra = @{}
        if ($PlanPath) { $extra.PlanPath = $PlanPath }
        & $script:ScriptPath -ArtifactsPath $script:FixturePath `
            -MaxAgeDays 30 -KeepLatestPerWorkflow 1 -MaxTotalSizeBytes 157286400 `
            -ReferenceDate '2026-07-01T00:00:00Z' -DryRun:$DryRun @extra
    }
}

Describe 'Invoke-ArtifactCleanup.ps1 CLI' {

    It 'prints exact RESULT lines for the sample fixture in dry-run mode' {
        $output = Invoke-Cli -DryRun | Out-String

        $output | Should -Match ([regex]::Escape('RESULT Mode=DRY-RUN'))
        $output | Should -Match ([regex]::Escape('RESULT TotalArtifacts=5'))
        $output | Should -Match ([regex]::Escape('RESULT DeletedCount=2'))
        $output | Should -Match ([regex]::Escape('RESULT RetainedCount=3'))
        $output | Should -Match ([regex]::Escape('RESULT SpaceReclaimedBytes=136314880'))
        $output | Should -Match ([regex]::Escape('RESULT RetainedSizeBytes=136314880'))
    }

    It 'lists each planned deletion with its reason' {
        $output = Invoke-Cli -DryRun | Out-String

        $output | Should -Match ([regex]::Escape('DELETE build-logs-run1001 reason=MaxAge'))
        $output | Should -Match ([regex]::Escape('DELETE build-logs-run1002 reason=MaxTotalSize'))
    }

    It 'reports EXECUTE mode and performs the (mock) deletions when not dry-run' {
        $output = Invoke-Cli | Out-String

        $output | Should -Match ([regex]::Escape('RESULT Mode=EXECUTE'))
        $output | Should -Match ([regex]::Escape("Deleted artifact 'build-logs-run1001'"))
        $output | Should -Match ([regex]::Escape("Deleted artifact 'build-logs-run1002'"))
    }

    It 'writes the full plan as JSON when -PlanPath is given' {
        $planFile = Join-Path ([System.IO.Path]::GetTempPath()) "plan-$([guid]::NewGuid()).json"
        try {
            Invoke-Cli -DryRun -PlanPath $planFile | Out-Null

            Test-Path $planFile | Should -BeTrue
            $plan = Get-Content $planFile -Raw | ConvertFrom-Json
            $plan.Summary.DeletedCount | Should -Be 2
            ($plan.Deleted.Name | Sort-Object) | Should -Be @('build-logs-run1001', 'build-logs-run1002')
        }
        finally {
            Remove-Item $planFile -ErrorAction SilentlyContinue
        }
    }

    It 'fails with a meaningful error when the artifacts file does not exist' {
        { & $script:ScriptPath -ArtifactsPath '/nonexistent/artifacts.json' -DryRun } |
            Should -Throw '*Artifacts file not found*'
    }

    It 'fails with a meaningful error when the artifacts file is not valid JSON' {
        $badFile = Join-Path ([System.IO.Path]::GetTempPath()) "bad-$([guid]::NewGuid()).json"
        Set-Content -Path $badFile -Value '{ not json ]'
        try {
            { & $script:ScriptPath -ArtifactsPath $badFile -DryRun } |
                Should -Throw '*not valid JSON*'
        }
        finally {
            Remove-Item $badFile -ErrorAction SilentlyContinue
        }
    }
}
