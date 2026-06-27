#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Integration + structure tests for the GitHub Actions workflow.

    * Structure tests parse the YAML and assert triggers/jobs/steps and that
      every referenced script path actually exists, plus actionlint exit 0.
    * Integration tests run the workflow end-to-end through `act` for two
      fixture cases (each in its own throwaway git repo), capture the output to
      act-result.txt, and assert the EXACT expected RESULT_* values and that
      every job reports "Job succeeded".

    To stay within a tight `act` budget, both cases are executed once in
    BeforeAll (2 act runs total); the It blocks only assert on captured output.
#>

BeforeAll {
    $script:ProjectDir   = Split-Path -Parent $PSCommandPath
    $script:WorkflowPath = Join-Path $script:ProjectDir '.github/workflows/artifact-cleanup-script.yml'
    $script:ActResult    = Join-Path $script:ProjectDir 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = (Get-Content -LiteralPath $script:WorkflowPath -Raw) | ConvertFrom-Yaml

    # The files every test case's temp repo needs.
    $script:ProjectFiles = @(
        'ArtifactCleanup.psm1',
        'ArtifactCleanup.Tests.ps1',
        'Invoke-Cleanup.ps1',
        '.actrc'
    )

    # Run one fixture case through act in an isolated temp git repo.
    function Invoke-ActCase {
        param(
            [Parameter(Mandatory)][string] $CaseName,
            [Parameter(Mandatory)][string] $ArtifactsJson,
            [Parameter(Mandatory)][string] $PolicyJson
        )

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("actcase_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            # Stage project files.
            foreach ($f in $script:ProjectFiles) {
                Copy-Item -LiteralPath (Join-Path $script:ProjectDir $f) -Destination (Join-Path $tmp $f) -Force
            }
            Copy-Item -LiteralPath (Join-Path $script:ProjectDir '.github') -Destination (Join-Path $tmp '.github') -Recurse -Force

            # Stage this case's fixture data.
            New-Item -ItemType Directory -Path (Join-Path $tmp 'fixtures') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tmp 'fixtures/artifacts.json') -Value $ArtifactsJson -NoNewline
            Set-Content -LiteralPath (Join-Path $tmp 'fixtures/policy.json')    -Value $PolicyJson    -NoNewline

            Push-Location $tmp
            try {
                # act needs a git repo with a commit to resolve the push event.
                git init -q 2>&1 | Out-Null
                git config user.email 'ci@example.com' 2>&1 | Out-Null
                git config user.name  'ci' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m "fixture: $CaseName" 2>&1 | Out-Null

                # --pull=false: the act-ubuntu-pwsh image is local-only.
                $out = & act push --rm --pull=false 2>&1 | Out-String
                $code = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            # Append delimited output to the required artifact file.
            $delim = ('=' * 70)
            Add-Content -LiteralPath $script:ActResult -Value @"
$delim
TEST CASE: $CaseName  (act exit code: $code)
$delim
$out
"@
            return [PSCustomObject]@{ Name = $CaseName; ExitCode = $code; Output = $out }
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- Fixture: Case A (age + keep-latest, dry-run) -------------------------
    $caseAArtifacts = @'
[
  { "Name": "build-1",     "Size": 1000, "CreatedAt": "2026-06-26T00:00:00Z", "WorkflowRunId": "100" },
  { "Name": "build-2",     "Size": 1500, "CreatedAt": "2026-06-20T00:00:00Z", "WorkflowRunId": "100" },
  { "Name": "build-3",     "Size": 2000, "CreatedAt": "2026-06-10T00:00:00Z", "WorkflowRunId": "100" },
  { "Name": "test-1",      "Size":  500, "CreatedAt": "2026-06-25T00:00:00Z", "WorkflowRunId": "200" },
  { "Name": "old-archive", "Size": 3000, "CreatedAt": "2026-01-01T00:00:00Z", "WorkflowRunId": "300" }
]
'@
    $caseAPolicy = @'
{ "MaxAgeDays": 30, "KeepLatestPerWorkflow": 2, "MaxTotalSize": 0, "DryRun": true }
'@

    # --- Fixture: Case B (total-size cap, live) -------------------------------
    $caseBArtifacts = @'
[
  { "Name": "a", "Size": 400, "CreatedAt": "2026-06-26T00:00:00Z", "WorkflowRunId": "10" },
  { "Name": "b", "Size": 400, "CreatedAt": "2026-06-25T00:00:00Z", "WorkflowRunId": "10" },
  { "Name": "c", "Size": 400, "CreatedAt": "2026-06-24T00:00:00Z", "WorkflowRunId": "20" },
  { "Name": "d", "Size": 400, "CreatedAt": "2026-06-23T00:00:00Z", "WorkflowRunId": "20" }
]
'@
    $caseBPolicy = @'
{ "MaxAgeDays": 0, "KeepLatestPerWorkflow": 0, "MaxTotalSize": 1000, "DryRun": false }
'@

    # Fresh artifact file for this run.
    Set-Content -LiteralPath $script:ActResult -Value "act-result.txt - generated by WorkflowAct.Tests.ps1`n"

    $script:CaseA = Invoke-ActCase -CaseName 'A-age-keeplatest-dryrun' -ArtifactsJson $caseAArtifacts -PolicyJson $caseAPolicy
    $script:CaseB = Invoke-ActCase -CaseName 'B-maxtotalsize-live'    -ArtifactsJson $caseBArtifacts -PolicyJson $caseBPolicy
}

Describe 'Workflow structure' {
    It 'declares all expected trigger events' {
        # 'on' parses to the key True under YAML 1.1; handle both spellings.
        $on = if ($script:Workflow.Contains('on')) { $script:Workflow['on'] } else { $script:Workflow[$true] }
        $on.Keys | Should -Contain 'push'
        $on.Keys | Should -Contain 'pull_request'
        $on.Keys | Should -Contain 'schedule'
        $on.Keys | Should -Contain 'workflow_dispatch'
    }
    It 'defines the test and cleanup jobs with a dependency between them' {
        $script:Workflow.jobs.Keys | Should -Contain 'test'
        $script:Workflow.jobs.Keys | Should -Contain 'cleanup'
        $script:Workflow.jobs.cleanup.needs | Should -Be 'test'
    }
    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($job in 'test', 'cleanup') {
            ($script:Workflow.jobs.$job.steps.uses) | Should -Contain 'actions/checkout@v4'
        }
    }
    It 'runs its run-steps with the pwsh shell' {
        $runSteps = @($script:Workflow.jobs.test.steps + $script:Workflow.jobs.cleanup.steps) |
            Where-Object { $_.run }
        $runSteps | Should -Not -BeNullOrEmpty
        foreach ($s in $runSteps) { $s.shell | Should -Be 'pwsh' }
    }
    It 'declares least-privilege permissions' {
        $script:Workflow.permissions.contents | Should -Be 'read'
    }
    It 'references script and fixture paths that exist on disk' {
        foreach ($p in 'Invoke-Cleanup.ps1', 'ArtifactCleanup.psm1', 'ArtifactCleanup.Tests.ps1',
                       'fixtures/artifacts.json', 'fixtures/policy.json') {
            Test-Path (Join-Path $script:ProjectDir $p) | Should -BeTrue -Because "$p is referenced by the workflow"
        }
    }
}

Describe 'actionlint' {
    It 'passes with exit code 0' {
        $null = & actionlint $script:WorkflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'act integration: Case A (age + keep-latest, dry-run)' {
    It 'exits 0' { $script:CaseA.ExitCode | Should -Be 0 }
    It 'reports both jobs succeeded' {
        ([regex]::Matches($script:CaseA.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        $script:CaseA.Output | Should -Not -Match 'Job failed'
    }
    It 'produces the exact expected plan totals' {
        $script:CaseA.Output | Should -Match 'RESULT_TOTAL=5(\D|$)'
        $script:CaseA.Output | Should -Match 'RESULT_RETAINED=3(\D|$)'
        $script:CaseA.Output | Should -Match 'RESULT_DELETED=2(\D|$)'
        $script:CaseA.Output | Should -Match 'RESULT_RECLAIMED=5000(\D|$)'
        $script:CaseA.Output | Should -Match 'RESULT_RETAINED_SIZE=3000(\D|$)'
        $script:CaseA.Output | Should -Match 'RESULT_DRYRUN=true(\D|$)'
    }
    It 'does not actually delete in dry-run mode' {
        $script:CaseA.Output | Should -Not -Match 'DELETED: '
    }
}

Describe 'act integration: Case B (max-total-size, live)' {
    It 'exits 0' { $script:CaseB.ExitCode | Should -Be 0 }
    It 'reports both jobs succeeded' {
        ([regex]::Matches($script:CaseB.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
        $script:CaseB.Output | Should -Not -Match 'Job failed'
    }
    It 'produces the exact expected plan totals' {
        $script:CaseB.Output | Should -Match 'RESULT_TOTAL=4(\D|$)'
        $script:CaseB.Output | Should -Match 'RESULT_RETAINED=2(\D|$)'
        $script:CaseB.Output | Should -Match 'RESULT_DELETED=2(\D|$)'
        $script:CaseB.Output | Should -Match 'RESULT_RECLAIMED=800(\D|$)'
        $script:CaseB.Output | Should -Match 'RESULT_RETAINED_SIZE=800(\D|$)'
        $script:CaseB.Output | Should -Match 'RESULT_DRYRUN=false(\D|$)'
    }
    It 'performs the deletions in live mode' {
        $script:CaseB.Output | Should -Match 'DELETED: c '
        $script:CaseB.Output | Should -Match 'DELETED: d '
    }
}
