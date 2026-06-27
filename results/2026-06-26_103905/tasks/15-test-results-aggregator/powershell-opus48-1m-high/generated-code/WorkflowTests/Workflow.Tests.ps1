# Workflow tests: structural validation of the GitHub Actions workflow, plus an
# end-to-end harness that runs the workflow through `act` (nektos/act) for each
# fixture test case and asserts on EXACT expected output.
#
# This file lives outside ./Tests on purpose: the workflow's own unit-test job
# runs `Invoke-Pester -Path ./Tests`, and we must never run `act` from inside an
# act container (act-in-act). The act cases are additionally guarded by $env:ACT.

BeforeDiscovery {
    # Decide at discovery time whether the act cases can run, so we can -Skip
    # them cleanly when act/Docker is unavailable or when we are already in act.
    $script:CanRunAct = [bool](Get-Command act -ErrorAction SilentlyContinue) -and (-not $env:ACT)
}

BeforeAll {
    # Recompute here: variables set in BeforeDiscovery do not carry into the run
    # phase. The -Skip expressions use the BeforeDiscovery value; this drives the
    # act block below. Both are computed identically so they always agree.
    $script:CanRunAct = [bool](Get-Command act -ErrorAction SilentlyContinue) -and (-not $env:ACT)

    $script:Root     = Split-Path $PSScriptRoot -Parent
    $script:Workflow = Join-Path $script:Root '.github/workflows/test-results-aggregator.yml'
    Import-Module powershell-yaml -Force
    $script:Doc = ConvertFrom-Yaml (Get-Content -LiteralPath $script:Workflow -Raw)

    # act-result.txt is a required artifact: every act case appends to it.
    $script:ActResult = Join-Path $script:Root 'act-result.txt'

    # --- Fixture content for each test case (filename -> file body) ------------

    # Case "flaky": the default matrix fixtures. Network.fetch passes on ubuntu
    # and macos but fails on windows -> exactly one flaky test.
    $script:FlakyFixtures = @{
        'run-ubuntu.xml' = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Calculator" tests="3" failures="0" skipped="1" time="0.20">
    <testcase classname="Calculator" name="add" time="0.10"/>
    <testcase classname="Calculator" name="subtract" time="0.10"/>
    <testcase classname="Calculator" name="divide_by_zero" time="0.00"><skipped/></testcase>
  </testsuite>
  <testsuite name="Network" tests="1" failures="0" time="0.50">
    <testcase classname="Network" name="fetch" time="0.50"/>
  </testsuite>
</testsuites>
'@
        'run-windows.xml' = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Calculator" tests="3" failures="0" skipped="1" time="0.23">
    <testcase classname="Calculator" name="add" time="0.12"/>
    <testcase classname="Calculator" name="subtract" time="0.11"/>
    <testcase classname="Calculator" name="divide_by_zero" time="0.00"><skipped/></testcase>
  </testsuite>
  <testsuite name="Network" tests="1" failures="1" time="0.40">
    <testcase classname="Network" name="fetch" time="0.40">
      <failure message="connection timed out">boom</failure>
    </testcase>
  </testsuite>
</testsuites>
'@
        'run-macos.json' = @'
{ "name": "macos", "tests": [
  { "name": "add",            "suite": "Calculator", "status": "passed",  "duration": 0.09 },
  { "name": "subtract",       "suite": "Calculator", "status": "passed",  "duration": 0.10 },
  { "name": "divide_by_zero", "suite": "Calculator", "status": "skipped", "duration": 0.00 },
  { "name": "fetch",          "suite": "Network",    "status": "passed",  "duration": 0.45 }
] }
'@
    }

    # Case "clean": two all-passing runs, no failures, no flakes.
    $script:CleanFixtures = @{
        'clean1.xml' = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="Smoke" tests="2" failures="0" time="0.30">
  <testcase classname="Smoke" name="ping" time="0.10"/>
  <testcase classname="Smoke" name="pong" time="0.20"/>
</testsuite></testsuites>
'@
        'clean2.json' = @'
{ "name": "Smoke", "tests": [
  { "name": "ping", "suite": "Smoke", "status": "passed", "duration": 0.10 },
  { "name": "pong", "suite": "Smoke", "status": "passed", "duration": 0.20 }
] }
'@
    }

    # --- Helper: run one fixture case end-to-end through act -------------------
    function script:Invoke-ActCase {
        param(
            [Parameter(Mandatory)] [string]$Name,
            [Parameter(Mandatory)] [hashtable]$Fixtures
        )

        # Build an isolated temp git repo containing the project + this case's
        # fixtures (and nothing from the default fixtures/ directory).
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("act-{0}-{1}" -f $Name, ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $work | Out-Null

        # Copy the pieces the workflow needs.
        Copy-Item (Join-Path $Root 'TestResultsAggregator.psm1') $work
        Copy-Item (Join-Path $Root 'Invoke-Aggregator.ps1') $work
        Copy-Item (Join-Path $Root '.actrc') $work
        Copy-Item (Join-Path $Root 'Tests') (Join-Path $work 'Tests') -Recurse
        New-Item -ItemType Directory -Path (Join-Path $work '.github/workflows') -Force | Out-Null
        Copy-Item $Workflow (Join-Path $work '.github/workflows/test-results-aggregator.yml')

        # Lay down this case's fixtures.
        $fixDir = Join-Path $work 'fixtures'
        New-Item -ItemType Directory -Path $fixDir | Out-Null
        foreach ($kv in $Fixtures.GetEnumerator()) {
            Set-Content -LiteralPath (Join-Path $fixDir $kv.Key) -Value $kv.Value -Encoding utf8
        }

        Push-Location $work
        try {
            git init -b main *> $null
            git config user.email 'ci@example.com' *> $null
            git config user.name 'CI' *> $null
            git add -A *> $null
            git commit -m "case $Name" *> $null

            # Run the workflow's push event. --rm cleans up the container after.
            # --pull=false: the custom act image is built locally and not in any
            # registry, so we must stop act from force-pulling it.
            $output = act push --rm --pull=false 2>&1 | Out-String
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        # Append to the required artifact with a clear delimiter.
        $delim = "`n========== ACT CASE: $Name (exit=$code) ==========`n"
        Add-Content -LiteralPath $ActResult -Value $delim
        Add-Content -LiteralPath $ActResult -Value $output

        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Name = $Name; ExitCode = $code; Output = $output }
    }

    # Run both cases up front so act executes exactly twice for this file.
    if ($script:CanRunAct) {
        Set-Content -LiteralPath $script:ActResult -Value "act test harness output`n" -Encoding utf8
        $script:FlakyRun = script:Invoke-ActCase -Name 'flaky' -Fixtures $script:FlakyFixtures
        $script:CleanRun = script:Invoke-ActCase -Name 'clean' -Fixtures $script:CleanFixtures
    }
}

Describe 'Workflow structure' {
    It 'is named and defines the expected trigger events' {
        $script:Doc['name'] | Should -Be 'Test Results Aggregator'
        $triggers = $script:Doc['on'].Keys
        $triggers | Should -Contain 'push'
        $triggers | Should -Contain 'pull_request'
        $triggers | Should -Contain 'schedule'
        $triggers | Should -Contain 'workflow_dispatch'
    }

    It 'declares least-privilege permissions' {
        $script:Doc['permissions']['contents'] | Should -Be 'read'
    }

    It 'defines both jobs with the correct dependency' {
        $script:Doc['jobs'].Keys | Should -Contain 'unit-tests'
        $script:Doc['jobs'].Keys | Should -Contain 'aggregate'
        # aggregate must depend on unit-tests.
        $script:Doc['jobs']['aggregate']['needs'] | Should -Be 'unit-tests'
    }

    It 'checks out the repo with actions/checkout@v4 in every job' {
        foreach ($job in $script:Doc['jobs'].Values) {
            $uses = $job['steps'] | ForEach-Object { $_['uses'] } | Where-Object { $_ }
            $uses | Should -Contain 'actions/checkout@v4'
        }
    }

    It 'uses pwsh shell (not bash-invoked pwsh) for run steps' {
        $runSteps = $script:Doc['jobs'].Values |
            ForEach-Object { $_['steps'] } |
            Where-Object { $_.ContainsKey('run') }
        $runSteps.Count | Should -BeGreaterThan 0
        foreach ($s in $runSteps) { $s['shell'] | Should -Be 'pwsh' }
    }

    It 'references script files that actually exist on disk' {
        Test-Path (Join-Path $script:Root 'Invoke-Aggregator.ps1')       | Should -BeTrue
        Test-Path (Join-Path $script:Root 'TestResultsAggregator.psm1')  | Should -BeTrue
        Test-Path (Join-Path $script:Root 'Tests')                       | Should -BeTrue
        # The aggregate step invokes the CLI script by name.
        ($script:Doc['jobs']['aggregate']['steps'] |
            Where-Object { $_.ContainsKey('run') } |
            ForEach-Object { $_['run'] }) -join "`n" | Should -Match 'Invoke-Aggregator\.ps1'
    }
}

Describe 'actionlint validation' {
    It 'passes actionlint with exit code 0' {
        $null = & actionlint $script:Workflow 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Workflow end-to-end via act' {
    Context 'flaky case (default matrix fixtures)' {
        It 'act exits 0' -Skip:(-not $script:CanRunAct) {
            $script:FlakyRun.ExitCode | Should -Be 0
        }
        It 'every job reports Job succeeded (and none failed)' -Skip:(-not $script:CanRunAct) {
            ([regex]::Matches($script:FlakyRun.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
            $script:FlakyRun.Output | Should -Not -Match 'Job failed'
        }
        It 'emits the exact aggregate totals' -Skip:(-not $script:CanRunAct) {
            $o = $script:FlakyRun.Output
            $o | Should -BeLike '*| Total | 12 |*'
            $o | Should -BeLike '*| Passed | 8 |*'
            $o | Should -BeLike '*| Failed | 1 |*'
            $o | Should -BeLike '*| Skipped | 3 |*'
            $o | Should -BeLike '*| Duration | 1.97s |*'
            $o | Should -BeLike '*| Runs | 3 |*'
        }
        It 'reports exactly the one flaky test with exact pass/fail counts' -Skip:(-not $script:CanRunAct) {
            $script:FlakyRun.Output | Should -BeLike '*| Network | fetch | 2 | 1 |*'
        }
        It 'shows the failure banner' -Skip:(-not $script:CanRunAct) {
            $script:FlakyRun.Output | Should -BeLike '*1 of 12 test runs failed.*'
        }
    }

    Context 'clean case (all passing, no flakes)' {
        It 'act exits 0' -Skip:(-not $script:CanRunAct) {
            $script:CleanRun.ExitCode | Should -Be 0
        }
        It 'every job reports Job succeeded' -Skip:(-not $script:CanRunAct) {
            ([regex]::Matches($script:CleanRun.Output, 'Job succeeded')).Count | Should -BeGreaterOrEqual 2
            $script:CleanRun.Output | Should -Not -Match 'Job failed'
        }
        It 'emits the exact aggregate totals' -Skip:(-not $script:CanRunAct) {
            $o = $script:CleanRun.Output
            $o | Should -BeLike '*| Total | 4 |*'
            $o | Should -BeLike '*| Passed | 4 |*'
            $o | Should -BeLike '*| Failed | 0 |*'
            $o | Should -BeLike '*| Skipped | 0 |*'
            $o | Should -BeLike '*| Duration | 0.6s |*'
            $o | Should -BeLike '*| Runs | 2 |*'
        }
        It 'reports no flaky tests and an all-passed banner' -Skip:(-not $script:CanRunAct) {
            $script:CleanRun.Output | Should -BeLike '*No flaky tests detected.*'
            $script:CleanRun.Output | Should -BeLike '*All 4 tests passed.*'
        }
    }

    It 'wrote the act-result.txt artifact' -Skip:(-not $script:CanRunAct) {
        Test-Path $script:ActResult | Should -BeTrue
    }
}
