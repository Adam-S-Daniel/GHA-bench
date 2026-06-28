#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Workflow.Tests.ps1

    Two kinds of tests live here, separated by Pester tags:

      -Tag 'Structure'  Fast, host-side checks: the workflow YAML parses, has the
                        expected triggers/jobs/steps, references files that exist,
                        and passes actionlint (exit code 0).

      -Tag 'Act'        The end-to-end harness required by the task. For each test
                        case it builds an isolated temporary git repo containing
                        the project + that case's fixture data, runs the workflow
                        with `act push --rm`, appends the full output to
                        act-result.txt, and asserts on EXACT expected values
                        (totals, flaky tests, "Job succeeded", exit code 0).

    Run only the fast checks:   Invoke-Pester -Path tests/Workflow.Tests.ps1 -Tag Structure
    Run the full act harness:   Invoke-Pester -Path tests/Workflow.Tests.ps1 -Tag Act
#>

# ---------------------------------------------------------------------------
# File-scope helpers. Defined at the top so they are available during the
# Pester run phase. They derive every path from $PSScriptRoot (this file's
# directory), so they work regardless of the caller's current directory.
# ---------------------------------------------------------------------------

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function New-ActCaseRepo {
    <#
        Assembles an isolated temp git repo for one act test case: copies the
        project files needed by the workflow and writes the case's fixtures into
        a fresh fixtures/ directory. Returns the repo path (logs are written to a
        sibling dir so act never copies them into the container).
    #>
    param(
        [Parameter(Mandatory)] [string] $CaseName,
        [Parameter(Mandatory)] [string] $JUnitXml,
        [Parameter(Mandatory)] [string] $Json
    )

    $root    = Get-ProjectRoot
    $caseDir = Join-Path ([System.IO.Path]::GetTempPath()) ("act-" + $CaseName + "-" + [System.IO.Path]::GetRandomFileName())
    $repo    = Join-Path $caseDir 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null

    # Copy only what the workflow needs (NOT this harness file, so act never
    # tries to launch act inside the runner).
    New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'tests') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'fixtures') -Force | Out-Null
    Copy-Item (Join-Path $root 'src' 'TestResultsAggregator.psm1')          (Join-Path $repo 'src')   -Force
    Copy-Item (Join-Path $root 'tests' 'TestResultsAggregator.Tests.ps1')   (Join-Path $repo 'tests') -Force
    Copy-Item (Join-Path $root 'Invoke-Aggregator.ps1')                     $repo -Force
    Copy-Item (Join-Path $root '.actrc')                                    $repo -Force
    Copy-Item (Join-Path $root '.github') $repo -Recurse -Force

    # Write THIS case's fixtures (a fresh fixtures/ for every case).
    Set-Content -Path (Join-Path $repo 'fixtures' 'run1-junit.xml')   -Value $JUnitXml -Encoding utf8
    Set-Content -Path (Join-Path $repo 'fixtures' 'run2-results.json') -Value $Json    -Encoding utf8

    # Initialize a git repo on 'main' so act's push event matches the workflow's
    # branch filter, then commit so there is a HEAD to run against.
    git -C $repo init -b main -q
    git -C $repo config user.email 'harness@example.com'
    git -C $repo config user.name  'Act Harness'
    git -C $repo add -A
    git -C $repo commit -q -m "act case: $CaseName"

    return $repo
}

function Invoke-ActPush {
    <#
        Runs `act push` in the given repo and returns @{ ExitCode; Output }.
        Uses the local custom image and cached actions only (no network), and a
        hard timeout so a stuck container can never hang the test suite.
    #>
    param(
        [Parameter(Mandatory)] [string] $RepoPath
    )

    $logDir = Split-Path -Parent $RepoPath
    $stdout = Join-Path $logDir 'act-stdout.log'
    $stderr = Join-Path $logDir 'act-stderr.log'

    $actArgs = @(
        'push'
        '--rm'
        '--pull=false'             # use the local act-ubuntu-pwsh image, never pull
        '--action-offline-mode'    # use the cached actions/checkout, never fetch
        '-P', 'ubuntu-latest=act-ubuntu-pwsh:latest'
    )

    $proc = Start-Process -FilePath 'act' -ArgumentList $actArgs `
        -WorkingDirectory $RepoPath -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    if (-not $proc.WaitForExit(420000)) {   # 7 minute ceiling
        try { $proc.Kill() } catch { }
        return @{ ExitCode = 124; Output = "ERROR: act timed out after 420s.`n" }
    }

    $out = ''
    if (Test-Path $stdout) { $out += (Get-Content -LiteralPath $stdout -Raw) }
    if (Test-Path $stderr) { $out += "`n" + (Get-Content -LiteralPath $stderr -Raw) }

    # Strip ANSI escape sequences so the saved artifact is human-readable plain
    # text and assertions can never be tripped by stray color codes.
    $ansi = [regex]::new("\x1b\[[0-9;?]*[ -/]*[@-~]")
    $out = $ansi.Replace($out, '')

    return @{ ExitCode = $proc.ExitCode; Output = $out }
}

function Add-ActResult {
    <#
        Appends one case's full act output to act-result.txt with a clear,
        machine-greppable delimiter block.
    #>
    param(
        [Parameter(Mandatory)] [string] $CaseName,
        [Parameter(Mandatory)] [int]    $ExitCode,
        [Parameter(Mandatory)] [string] $Output
    )
    $file = Join-Path (Get-ProjectRoot) 'act-result.txt'
    $block = @()
    $block += '==================================================================='
    $block += "TEST CASE: $CaseName"
    $block += 'COMMAND: act push --rm --pull=false --action-offline-mode -P ubuntu-latest=act-ubuntu-pwsh:latest'
    $block += "EXIT CODE: $ExitCode"
    $block += '-------------------------------------------------------------------'
    $block += $Output
    $block += '=================================================================== END CASE'
    $block += ''
    Add-Content -LiteralPath $file -Value ($block -join "`n")
}

# ===========================================================================
# Structure tests (fast, host-side)
# ===========================================================================

Describe 'Workflow structure' -Tag 'Structure' {

    BeforeAll {
        $script:root         = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:workflowPath = Join-Path $script:root '.github' 'workflows' 'test-results-aggregator.yml'

        Import-Module powershell-yaml -ErrorAction Stop
        $script:yaml = Get-Content -LiteralPath $script:workflowPath -Raw | ConvertFrom-Yaml

        # YAML parsers sometimes read the 'on:' key as the boolean true; handle both.
        $script:triggers = if ($script:yaml.Contains('on')) { $script:yaml['on'] } else { $script:yaml[$true] }
        $script:jobs     = $script:yaml['jobs']
    }

    It 'has a workflow file at the expected path' {
        Test-Path -LiteralPath $script:workflowPath | Should -BeTrue
    }

    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:workflowPath 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'declares a workflow name' {
        $script:yaml['name'] | Should -Not -BeNullOrEmpty
    }

    It 'defines the expected trigger events' {
        $keys = @($script:triggers.Keys)
        $keys | Should -Contain 'push'
        $keys | Should -Contain 'pull_request'
        $keys | Should -Contain 'schedule'
        $keys | Should -Contain 'workflow_dispatch'
    }

    It 'sets least-privilege read-only permissions' {
        $script:yaml['permissions']['contents'] | Should -BeExactly 'read'
    }

    It 'defines two jobs with a needs dependency between them' {
        @($script:jobs.Keys) | Should -Contain 'unit-tests'
        @($script:jobs.Keys) | Should -Contain 'aggregate'
        @($script:jobs['aggregate']['needs']) | Should -Contain 'unit-tests'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($jobName in $script:jobs.Keys) {
            $uses = @($script:jobs[$jobName]['steps'] | ForEach-Object { $_['uses'] })
            $uses | Should -Contain 'actions/checkout@v4' -Because "job '$jobName' should check out the repo"
        }
    }

    It 'runs the aggregator script via shell: pwsh' {
        $aggSteps = @($script:jobs['aggregate']['steps'] | Where-Object { $_.ContainsKey('run') })
        ($aggSteps | Where-Object { $_['shell'] -eq 'pwsh' }) | Should -Not -BeNullOrEmpty
        ($aggSteps | Where-Object { $_['run'] -match 'Invoke-Aggregator\.ps1' }) | Should -Not -BeNullOrEmpty
    }

    It 'runs the Pester unit tests via shell: pwsh in the unit-tests job' {
        $utSteps = @($script:jobs['unit-tests']['steps'] | Where-Object { $_.ContainsKey('run') })
        ($utSteps | Where-Object { $_['shell'] -eq 'pwsh' }) | Should -Not -BeNullOrEmpty
        ($utSteps | Where-Object { $_['run'] -match 'TestResultsAggregator\.Tests\.ps1' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Referenced files exist on disk' -Tag 'Structure' {

    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    It 'ships the aggregator CLI entry point' {
        Test-Path -LiteralPath (Join-Path $script:root 'Invoke-Aggregator.ps1') | Should -BeTrue
    }

    It 'ships the module the workflow depends on' {
        Test-Path -LiteralPath (Join-Path $script:root 'src' 'TestResultsAggregator.psm1') | Should -BeTrue
    }

    It 'ships the unit test file the workflow runs' {
        Test-Path -LiteralPath (Join-Path $script:root 'tests' 'TestResultsAggregator.Tests.ps1') | Should -BeTrue
    }

    It 'ships sample JUnit XML and JSON fixtures' {
        @(Get-ChildItem (Join-Path $script:root 'fixtures') -Filter *.xml).Count  | Should -BeGreaterThan 0
        @(Get-ChildItem (Join-Path $script:root 'fixtures') -Filter *.json).Count | Should -BeGreaterThan 0
    }
}

# ===========================================================================
# Act end-to-end harness (slow; every assertion is on an EXACT value)
# ===========================================================================

Describe 'Workflow execution via act' -Tag 'Act' {

    BeforeAll {
        # Start a fresh act-result.txt for this run (required artifact).
        $script:actResultFile = Join-Path (Get-ProjectRoot) 'act-result.txt'
        $header = @(
            "act-result.txt"
            "Generated by tests/Workflow.Tests.ps1 (Tag 'Act')."
            "Each block below is one workflow execution through nektos/act."
            ""
        ) -join "`n"
        Set-Content -LiteralPath $script:actResultFile -Value $header -Encoding utf8

        # ----- Fixture data for each case (kept inline so cases are self-describing) -----

        # Case A: a genuinely flaky test. Calc.divide fails in leg 1, passes in
        # leg 2. Expected totals: 5 passed, 1 failed, 2 skipped, 8 total, 0.71s.
        $script:caseA_xml = @'
<testsuites>
  <testsuite name="CalcSuite" tests="4" failures="1" skipped="1" time="0.35">
    <testcase name="add"      classname="Calc" time="0.10" />
    <testcase name="subtract" classname="Calc" time="0.20" />
    <testcase name="divide"   classname="Calc" time="0.05"><failure message="divide by zero" /></testcase>
    <testcase name="legacy"   classname="Calc" time="0.00"><skipped /></testcase>
  </testsuite>
</testsuites>
'@
        $script:caseA_json = @'
{
  "suite": "CalcSuite",
  "tests": [
    { "name": "Calc.add",      "status": "passed",  "duration": 0.12 },
    { "name": "Calc.subtract", "status": "passed",  "duration": 0.18 },
    { "name": "Calc.divide",   "status": "passed",  "duration": 0.06 },
    { "name": "Calc.legacy",   "status": "skipped", "duration": 0.00 }
  ]
}
'@

        # Case B: NO flaky tests, but Api.brokenFeature fails in BOTH legs (a
        # stable failure, which must NOT be reported as flaky). Expected totals:
        # 4 passed, 2 failed, 2 skipped, 8 total, 0.92s; flaky count 0.
        $script:caseB_xml = @'
<testsuites>
  <testsuite name="ApiSuite" tests="4" failures="1" skipped="1" time="0.45">
    <testcase name="login"         classname="Api" time="0.30" />
    <testcase name="logout"        classname="Api" time="0.10" />
    <testcase name="brokenFeature" classname="Api" time="0.05"><failure message="HTTP 500" /></testcase>
    <testcase name="timeout"       classname="Api" time="0.00"><skipped /></testcase>
  </testsuite>
</testsuites>
'@
        $script:caseB_json = @'
{
  "suite": "ApiSuite",
  "tests": [
    { "name": "Api.login",         "status": "passed",  "duration": 0.32 },
    { "name": "Api.logout",        "status": "passed",  "duration": 0.11 },
    { "name": "Api.brokenFeature", "status": "failed",  "duration": 0.04 },
    { "name": "Api.timeout",       "status": "skipped", "duration": 0.00 }
  ]
}
'@

        # Run both cases ONCE here (act is expensive) and stash the results so
        # the It blocks below only assert. This keeps the run to one act push
        # per case.
        $repoA = New-ActCaseRepo -CaseName 'flaky'  -JUnitXml $script:caseA_xml -Json $script:caseA_json
        $script:resultA = Invoke-ActPush -RepoPath $repoA
        Add-ActResult -CaseName 'flaky' -ExitCode $script:resultA.ExitCode -Output $script:resultA.Output
        Remove-Item -LiteralPath (Split-Path -Parent $repoA) -Recurse -Force -ErrorAction SilentlyContinue

        $repoB = New-ActCaseRepo -CaseName 'stable' -JUnitXml $script:caseB_xml -Json $script:caseB_json
        $script:resultB = Invoke-ActPush -RepoPath $repoB
        Add-ActResult -CaseName 'stable' -ExitCode $script:resultB.ExitCode -Output $script:resultB.Output
        Remove-Item -LiteralPath (Split-Path -Parent $repoB) -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Case A: a flaky test across the matrix' {

        It 'act exits with code 0' {
            $script:resultA.ExitCode | Should -Be 0
        }

        It 'both jobs report "Job succeeded"' {
            $count = ([regex]::Matches($script:resultA.Output, 'Job succeeded')).Count
            $count | Should -BeGreaterOrEqual 2
            $script:resultA.Output | Should -Not -Match 'Job failed'
        }

        It 'runs all 28 unit tests through the pipeline with zero failures' {
            $script:resultA.Output | Should -Match 'Pester: 28 passed, 0 failed'
        }

        It 'computes the exact aggregated totals' {
            $script:resultA.Output | Should -BeLike '*AGG_TOTALS passed=5 failed=1 skipped=2 total=8 duration=0.71 runs=2*'
        }

        It 'detects exactly one flaky test: Calc.divide' {
            $script:resultA.Output | Should -BeLike '*AGG_FLAKY_COUNT 1*'
            $script:resultA.Output | Should -BeLike '*AGG_FLAKY_TEST Calc.divide passed=1 failed=1*'
        }
    }

    Context 'Case B: a stable failure (must not be flagged flaky)' {

        It 'act exits with code 0' {
            $script:resultB.ExitCode | Should -Be 0
        }

        It 'both jobs report "Job succeeded"' {
            $count = ([regex]::Matches($script:resultB.Output, 'Job succeeded')).Count
            $count | Should -BeGreaterOrEqual 2
            $script:resultB.Output | Should -Not -Match 'Job failed'
        }

        It 'computes the exact aggregated totals' {
            $script:resultB.Output | Should -BeLike '*AGG_TOTALS passed=4 failed=2 skipped=2 total=8 duration=0.92 runs=2*'
        }

        It 'reports zero flaky tests (the stable failure is excluded)' {
            $script:resultB.Output | Should -BeLike '*AGG_FLAKY_COUNT 0*'
            $script:resultB.Output | Should -Not -BeLike '*AGG_FLAKY_TEST*'
        }
    }
}
