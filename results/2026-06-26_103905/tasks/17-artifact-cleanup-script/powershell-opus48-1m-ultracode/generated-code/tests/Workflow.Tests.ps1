# Workflow.Tests.ps1
#
# Integration / workflow tests for the artifact-cleanup pipeline. These are
# distinct from the unit tests in ArtifactCleanup.Tests.ps1:
#
#   1. Workflow STRUCTURE   - parse the YAML, assert triggers/jobs/steps and
#                             that the referenced script paths actually exist.
#   2. actionlint           - assert the workflow passes static analysis.
#   3. End-to-end via `act` - for each fixture/test case, build a temp git repo,
#                             run the workflow with `act push --rm`, append the
#                             output to act-result.txt, and assert the exact
#                             expected values plus "Job succeeded" for every job.
#
# Each act test case runs the workflow exactly once (3 cases => 3 `act push`
# runs total). Set $env:SKIP_ACT='1' to skip the (slow) act section while
# iterating on the cheap structure/actionlint tests.
#
# Run with:  Invoke-Pester ./tests/Workflow.Tests.ps1

BeforeDiscovery {
    # Evaluated during discovery so it can drive -Skip and -ForEach below.
    $SkipAct = ($env:SKIP_ACT -eq '1')

    # The known-good expectations for each fixture/test case. Every "Expect"
    # string must appear verbatim in that case's act output. These are the exact
    # values computed from each fixture (not just "a number appeared").
    $ActCases = @(
        @{
            Name    = 'case-1-maxage'
            Fixture = 'fixtures/case-1-maxage.json'
            Expect  = @(
                'ACLEANUP::TotalArtifacts=4'
                'ACLEANUP::RetainedCount=2'
                'ACLEANUP::DeletedCount=2'
                'ACLEANUP::TotalSizeBytes=3800'
                'ACLEANUP::RetainedSizeBytes=800'
                'ACLEANUP::DeletedSizeBytes=3000'
                'ACLEANUP::SpaceReclaimedBytes=3000'
                'ACLEANUP::OverBudget=False'
                'ACLEANUP::DryRun=True'
                'ACLEANUP::Executed=False'
                'ACLEANUP::DeletedNames=old-jan,old-mar'
                'ACLEANUP::RetainedNames=jun-01,jun-27'
                'ACLEANUP::Result=OK'
            )
        }
        @{
            Name    = 'case-2-keeplatestn'
            Fixture = 'fixtures/case-2-keeplatestn.json'
            Expect  = @(
                'ACLEANUP::TotalArtifacts=5'
                'ACLEANUP::RetainedCount=3'
                'ACLEANUP::DeletedCount=2'
                'ACLEANUP::TotalSizeBytes=450'
                'ACLEANUP::RetainedSizeBytes=250'
                'ACLEANUP::DeletedSizeBytes=200'
                'ACLEANUP::SpaceReclaimedBytes=200'
                'ACLEANUP::OverBudget=False'
                'ACLEANUP::DryRun=False'
                'ACLEANUP::Executed=True'
                'ACLEANUP::DeletedNames=a1,a2'
                'ACLEANUP::RetainedNames=a3,a4,b1'
                'ACLEANUP::Result=OK'
            )
        }
        @{
            Name    = 'case-3-combo'
            Fixture = 'fixtures/case-3-combo.json'
            Expect  = @(
                'ACLEANUP::TotalArtifacts=5'
                'ACLEANUP::RetainedCount=2'
                'ACLEANUP::DeletedCount=3'
                'ACLEANUP::TotalSizeBytes=5000'
                'ACLEANUP::RetainedSizeBytes=2000'
                'ACLEANUP::DeletedSizeBytes=3000'
                'ACLEANUP::SpaceReclaimedBytes=3000'
                'ACLEANUP::OverBudget=False'
                'ACLEANUP::DryRun=True'
                'ACLEANUP::Executed=False'
                'ACLEANUP::DeletedNames=v1,v2,v3'
                'ACLEANUP::RetainedNames=v4,v5'
                'ACLEANUP::Result=OK'
            )
        }
    )
}

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:WorkflowPath = Join-Path $script:RepoRoot '.github/workflows/artifact-cleanup-script.yml'
    $script:ActResult    = Join-Path $script:RepoRoot 'act-result.txt'

    Import-Module powershell-yaml -ErrorAction Stop
    $script:Workflow = Get-Content $script:WorkflowPath -Raw | ConvertFrom-Yaml

    # Robustly fetch the 'on:' triggers node (YAML 1.1 can map 'on' -> $true).
    $script:Triggers = if ($script:Workflow.Contains('on')) { $script:Workflow['on'] }
                       elseif ($script:Workflow.Contains($true)) { $script:Workflow[$true] }
                       else { @{} }
}

Describe 'Workflow file structure' {
    It 'is valid parseable YAML with the expected name' {
        $script:Workflow         | Should -Not -BeNullOrEmpty
        $script:Workflow['name'] | Should -Be 'Artifact Cleanup'
    }

    It 'declares the expected trigger events' {
        $keys = @($script:Triggers.Keys)
        $keys | Should -Contain 'push'
        $keys | Should -Contain 'pull_request'
        $keys | Should -Contain 'schedule'
        $keys | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege permissions' {
        $script:Workflow['permissions']             | Should -Not -BeNullOrEmpty
        $script:Workflow['permissions']['contents'] | Should -Be 'read'
        $script:Workflow['permissions']['actions']  | Should -Be 'write'
    }

    It 'defines a workflow-level FIXTURE_PATH env var' {
        $script:Workflow['env']['FIXTURE_PATH'] | Should -Be 'fixtures/case.json'
    }

    It 'has the two expected jobs with a dependency between them' {
        $jobs = $script:Workflow['jobs']
        $jobs.Keys | Should -Contain 'unit-tests'
        $jobs.Keys | Should -Contain 'cleanup-plan'
        @($jobs['cleanup-plan']['needs']) | Should -Contain 'unit-tests'
    }

    It 'uses actions/checkout@v4 in both jobs' {
        foreach ($jobName in 'unit-tests', 'cleanup-plan') {
            $uses = @($script:Workflow['jobs'][$jobName]['steps'] | ForEach-Object { $_['uses'] })
            ($uses -contains 'actions/checkout@v4') | Should -BeTrue -Because "$jobName should check out the repo"
        }
    }

    It 'runs its cleanup-plan script steps with shell: pwsh' {
        $runSteps = $script:Workflow['jobs']['cleanup-plan']['steps'] | Where-Object { $_.Contains('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) { $s['shell'] | Should -Be 'pwsh' }
    }

    It 'references the cleanup script by its real path' {
        $runText = ($script:Workflow['jobs']['cleanup-plan']['steps'] | ForEach-Object { $_['run'] }) -join "`n"
        $runText | Should -Match 'Invoke-ArtifactCleanup\.ps1'
    }
}

Describe 'Referenced project files exist on disk' {
    It 'has the engine module' {
        Test-Path (Join-Path $script:RepoRoot 'ArtifactCleanup.psm1') | Should -BeTrue
    }
    It 'has the CLI entry script' {
        Test-Path (Join-Path $script:RepoRoot 'Invoke-ArtifactCleanup.ps1') | Should -BeTrue
    }
    It 'has the unit test file the workflow runs' {
        Test-Path (Join-Path $script:RepoRoot 'tests/ArtifactCleanup.Tests.ps1') | Should -BeTrue
    }
    It 'has the default fixture referenced by FIXTURE_PATH' {
        Test-Path (Join-Path $script:RepoRoot 'fixtures/case.json') | Should -BeTrue
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        if (-not (Get-Command actionlint -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'actionlint not installed'; return
        }
        $out = & actionlint $script:WorkflowPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because "actionlint reported:`n$out"
    }
}

Describe 'End-to-end pipeline via act' -Skip:$SkipAct {
    BeforeAll {
        # Build a temp git repo with the project + the given case fixture, run
        # `act push --rm`, and return @{ ExitCode; Output }.
        function Invoke-ActCase {
            param([string] $FixtureRelPath)

            $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("act-cleanup-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $temp -Force | Out-Null
            try {
                # Copy the project files needed for the workflow to run.
                foreach ($item in 'ArtifactCleanup.psm1', 'Invoke-ArtifactCleanup.ps1', 'tests', 'fixtures', '.github', '.actrc') {
                    Copy-Item -Path (Join-Path $script:RepoRoot $item) -Destination $temp -Recurse -Force
                }
                # Overwrite the consumed fixture with this case's data.
                Copy-Item -Path (Join-Path $script:RepoRoot $FixtureRelPath) `
                          -Destination (Join-Path $temp 'fixtures/case.json') -Force

                Push-Location $temp
                try {
                    # Commit everything so actions/checkout@v4 sees the files.
                    git init -q 2>&1 | Out-Null
                    git config user.email 'ci@example.com' 2>&1 | Out-Null
                    git config user.name  'ci' 2>&1 | Out-Null
                    git add -A 2>&1 | Out-Null
                    git commit -q -m 'test case' 2>&1 | Out-Null

                    # Run the workflow. -P pins the local pwsh-enabled image,
                    # --pull=false keeps it offline, --rm cleans up the container.
                    $output = & act push --rm --pull=false `
                        -P 'ubuntu-latest=act-ubuntu-pwsh:latest' 2>&1 | Out-String
                    $code = $LASTEXITCODE
                }
                finally { Pop-Location }

                return @{ ExitCode = $code; Output = $output }
            }
            finally {
                Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Start a fresh results file; each case appends to it below.
        Set-Content -Path $script:ActResult -Value "Artifact Cleanup - act push results" -Encoding utf8
    }

    # One It per case => exactly one `act push` per case. All assertions for a
    # case live here so we never invoke act more than once per case.
    It 'case <Name>: runs through act and produces the exact expected plan' -ForEach $ActCases {
        $r = Invoke-ActCase -FixtureRelPath $Fixture

        # Append this case's output to act-result.txt, clearly delimited.
        $delim = "`n========== TEST CASE: $Name (exit=$($r.ExitCode)) ==========`n"
        Add-Content -Path $script:ActResult -Value $delim   -Encoding utf8
        Add-Content -Path $script:ActResult -Value $r.Output -Encoding utf8

        # 1) act must exit 0.
        $r.ExitCode | Should -Be 0 -Because "act output:`n$($r.Output)"

        # 2) every job must report success (two jobs: unit-tests, cleanup-plan).
        $r.Output | Should -Not -Match 'Job failed'
        ([regex]::Matches($r.Output, 'Job succeeded')).Count |
            Should -BeGreaterOrEqual 2 -Because "expected both jobs to succeed; output:`n$($r.Output)"

        # 3) exact expected values must appear in the output.
        foreach ($expected in $Expect) {
            $r.Output.Contains($expected) |
                Should -BeTrue -Because "expected '$expected' in act output:`n$($r.Output)"
        }
    }

    It 'wrote the required act-result.txt artifact with all cases' {
        Test-Path $script:ActResult | Should -BeTrue
        $content = Get-Content $script:ActResult -Raw
        $content | Should -Match 'case-1-maxage'
        $content | Should -Match 'case-2-keeplatestn'
        $content | Should -Match 'case-3-combo'
    }
}
