#Requires -Modules Pester
<#
    Tests for the Invoke-ArtifactCleanup.ps1 CLI wrapper: the script that the
    GitHub Actions workflow actually invokes. It reads an artifact inventory
    JSON file, applies retention policies via ArtifactCleanup.psm1, prints a
    machine-parseable summary line, and (unless -DryRun) writes out an
    updated inventory with deleted artifacts removed.
#>

BeforeAll {
    $script:CliPath = Join-Path $PSScriptRoot '..' 'Invoke-ArtifactCleanup.ps1'
    $script:FixturePath = Join-Path $PSScriptRoot '..' 'fixtures' 'sample-artifacts.json'
    $script:FixedNow = '2026-07-01T00:00:00Z'

    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("artifact-cleanup-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:WorkDir | Out-Null
}

AfterAll {
    if (Test-Path $script:WorkDir) {
        Remove-Item -Path $script:WorkDir -Recurse -Force
    }
}

Describe 'Invoke-ArtifactCleanup.ps1' {

    Context 'applying the age-only policy' {
        BeforeAll {
            $script:PlanPath = Join-Path $script:WorkDir 'age-plan.json'
            $script:RemainingPath = Join-Path $script:WorkDir 'age-remaining.json'

            $script:Output = & $script:CliPath -ArtifactsPath $script:FixturePath -MaxAgeDays 30 -Now $script:FixedNow `
                -ScenarioName 'age-policy' -PlanOutputPath $script:PlanPath -RemainingOutputPath $script:RemainingPath
        }

        It 'prints the exact expected machine-parseable summary line' {
            ($script:Output -join "`n") | Should -Match 'SCENARIO=age-policy DRYRUN=False RETAINED=4 DELETED=4 RECLAIMED_BYTES=796917760 TOTAL_BYTES=1321205760'
        }

        It 'writes a plan file with the retained and deleted artifacts' {
            Test-Path $script:PlanPath | Should -Be $true
            $plan = Get-Content -Raw -Path $script:PlanPath | ConvertFrom-Json
            $plan.Summary.RetainedCount | Should -Be 4
            $plan.Summary.DeletedCount | Should -Be 4
        }

        It 'writes a remaining-artifacts file containing only the retained artifacts' {
            Test-Path $script:RemainingPath | Should -Be $true
            $remaining = Get-Content -Raw -Path $script:RemainingPath | ConvertFrom-Json
            $remaining.Count | Should -Be 4
            ($remaining | ForEach-Object Name | Sort-Object) | Should -Be @('ci-build-1', 'ci-build-2', 'ci-build-3', 'deploy-1')
        }
    }

    Context 'DryRun mode' {
        BeforeAll {
            $script:DryPlanPath = Join-Path $script:WorkDir 'dry-plan.json'
            $script:DryRemainingPath = Join-Path $script:WorkDir 'dry-remaining.json'

            $script:Output = & $script:CliPath -ArtifactsPath $script:FixturePath -MaxAgeDays 30 -Now $script:FixedNow `
                -ScenarioName 'age-policy-dry' -DryRun -PlanOutputPath $script:DryPlanPath -RemainingOutputPath $script:DryRemainingPath
        }

        It 'reports DRYRUN=True in the summary line' {
            ($script:Output -join "`n") | Should -Match 'SCENARIO=age-policy-dry DRYRUN=True RETAINED=4 DELETED=4 RECLAIMED_BYTES=796917760'
        }

        It 'still writes the plan file (so callers can inspect what would happen)' {
            Test-Path $script:DryPlanPath | Should -Be $true
        }

        It 'does NOT write a remaining-artifacts file, since no deletion actually occurred' {
            Test-Path $script:DryRemainingPath | Should -Be $false
        }
    }

    Context 'error handling' {
        It 'throws a meaningful error when the artifacts file does not exist' {
            $missingPath = Join-Path $script:WorkDir 'does-not-exist.json'
            { & $script:CliPath -ArtifactsPath $missingPath -Now $script:FixedNow } | Should -Throw '*not found*'
        }

        It 'throws a meaningful error when the artifacts file contains invalid JSON' {
            $badJsonPath = Join-Path $script:WorkDir 'bad.json'
            Set-Content -Path $badJsonPath -Value '{ this is not valid json '
            { & $script:CliPath -ArtifactsPath $badJsonPath -Now $script:FixedNow } | Should -Throw '*JSON*'
        }
    }
}
