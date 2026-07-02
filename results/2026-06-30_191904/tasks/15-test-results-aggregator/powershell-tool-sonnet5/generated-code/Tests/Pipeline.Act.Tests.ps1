<#
    Pipeline.Act.Tests.ps1

    Per the task requirements, the aggregator script is NOT unit tested
    directly here. Instead, every test case runs the real GitHub Actions
    workflow end to end via `act push --rm` in Docker, and assertions are
    made against the captured job-log output. For each scenario this:

      1. Creates a fresh temp git repo containing the project files
         (script, module, workflow, .actrc) plus that scenario's fixture
         data copied into ./test-results
      2. Commits it and runs `act push --rm`
      3. Appends the full output to act-result.txt (delimited per scenario)
      4. Asserts exit code 0, exact aggregated totals, exact flaky-test
         detection, and "Job succeeded" for every job

    Two scenarios cover: (a) an all-passing multi-run matrix with skips and
    no flakiness, and (b) a mix of JUnit XML + JSON runs with a real
    (consistent) failure, a consistently-skipped test, and one genuinely
    flaky test (passed in one run, failed in another).
#>

BeforeDiscovery {
    $script:Scenarios = @(
        @{
            Name                = 'clean-matrix'
            FixtureDir          = 'fixtures/clean-matrix'
            ExpectedTotal       = 9
            ExpectedPassed      = 6
            ExpectedFailed      = 0
            ExpectedSkipped     = 3
            ExpectedDuration    = '0.90s'
            ExpectedFlakyCount  = 0
            ExpectedFlakyText   = 'No flaky tests detected across 3 run(s).'
        },
        @{
            Name                = 'flaky-and-failures'
            FixtureDir          = 'fixtures/flaky-and-failures'
            ExpectedTotal       = 8
            ExpectedPassed      = 3
            ExpectedFailed      = 3
            ExpectedSkipped     = 2
            ExpectedDuration    = '1.80s'
            ExpectedFlakyCount  = 1
            ExpectedFlakyText   = 'AuthService.test_login | 1 | 1 | 0'
        }
    )
}

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ActResultPath = Join-Path $script:ProjectRoot 'act-result.txt'
    $script:ProjectItems = @('Aggregate-TestResults.ps1', 'TestResultsAggregator.psm1', '.github', '.actrc')

    # Start each full test run with a clean act-result.txt so the file only
    # ever reflects the most recent run's evidence.
    if (Test-Path -LiteralPath $script:ActResultPath) {
        Remove-Item -LiteralPath $script:ActResultPath -Force
    }
    New-Item -ItemType File -Path $script:ActResultPath -Force | Out-Null

    function Invoke-ActScenario {
        param(
            [Parameter(Mandatory)][string]$ScenarioName,
            [Parameter(Mandatory)][string]$FixtureDir
        )

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aggregator-act-$ScenarioName-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            foreach ($item in $script:ProjectItems) {
                Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $item) -Destination $tempDir -Recurse -Force
            }

            $testResultsDest = Join-Path $tempDir 'test-results'
            New-Item -ItemType Directory -Path $testResultsDest -Force | Out-Null
            Copy-Item -Path (Join-Path $script:ProjectRoot $FixtureDir '*') -Destination $testResultsDest -Recurse -Force

            Push-Location $tempDir
            try {
                git init -q -b main 2>&1 | Out-Null
                git config user.email 'act-harness@example.com' 2>&1 | Out-Null
                git config user.name 'Act Test Harness' 2>&1 | Out-Null
                git add -A 2>&1 | Out-Null
                git commit -q -m "test: $ScenarioName scenario" 2>&1 | Out-Null

                # --pull=false: the ubuntu-latest -> act-ubuntu-pwsh:latest image mapping
                # in .actrc is a purely local image, so the default forced pull
                # (`act`'s --pull defaults to true) fails with a registry auth error.
                # The image is already present locally, so skip the pull.
                $output = & act push --rm --pull=false 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }

            return [PSCustomObject]@{
                ScenarioName = $ScenarioName
                Output       = $output
                ExitCode     = $exitCode
            }
        }
        finally {
            if (Test-Path -LiteralPath $tempDir) {
                Remove-Item -LiteralPath $tempDir -Recurse -Force
            }
        }
    }

    function Add-ActResultRecord {
        param(
            [Parameter(Mandatory)][string]$ScenarioName,
            [Parameter(Mandatory)][int]$ExitCode,
            [Parameter(Mandatory)][string]$Output
        )

        $delimiter = '=' * 80
        $header = "$delimiter`nSCENARIO: $ScenarioName`nEXIT CODE: $ExitCode`n$delimiter"
        Add-Content -LiteralPath $script:ActResultPath -Value $header
        Add-Content -LiteralPath $script:ActResultPath -Value $Output
        Add-Content -LiteralPath $script:ActResultPath -Value ''
    }
}

Describe 'Test Results Aggregator - Pipeline (via act)' {

    Context 'Scenario: <_.Name>' -ForEach $script:Scenarios {

        BeforeAll {
            # $Name, $FixtureDir, $ExpectedTotal, etc. are bound automatically
            # by Pester's -ForEach from each scenario hashtable's keys.
            $result = Invoke-ActScenario -ScenarioName $Name -FixtureDir $FixtureDir
            Add-ActResultRecord -ScenarioName $Name -ExitCode $result.ExitCode -Output $result.Output
        }

        It 'runs the workflow via act push and exits with code 0' {
            $result.ExitCode | Should -Be 0
        }

        It 'reports "Job succeeded" for both the collect and aggregate jobs' {
            $matches = [regex]::Matches($result.Output, 'Job succeeded')
            $matches.Count | Should -Be 2
        }

        It 'computes the expected total test count' {
            $result.Output.Contains("Total:** $ExpectedTotal") | Should -BeTrue -Because "output was:`n$($result.Output)"
        }

        It 'computes the expected passed count' {
            $result.Output.Contains("Passed:** $ExpectedPassed ") | Should -BeTrue -Because "output was:`n$($result.Output)"
        }

        It 'computes the expected failed count' {
            $result.Output.Contains("Failed:** $ExpectedFailed ") | Should -BeTrue -Because "output was:`n$($result.Output)"
        }

        It 'computes the expected skipped count' {
            $result.Output.Contains("Skipped:** $ExpectedSkipped ") | Should -BeTrue -Because "output was:`n$($result.Output)"
        }

        It 'computes the expected total duration' {
            $result.Output.Contains("Duration:** $ExpectedDuration") | Should -BeTrue -Because "output was:`n$($result.Output)"
        }

        It 'reports the expected flaky test detail' {
            $result.Output.Contains($ExpectedFlakyText) | Should -BeTrue -Because "output was:`n$($result.Output)"
        }
    }

    Context 'act-result.txt artifact' {
        It 'exists after the pipeline runs' {
            $script:ActResultPath | Should -Exist
        }

        It 'contains a delimited record for every scenario' {
            $content = Get-Content -LiteralPath $script:ActResultPath -Raw
            foreach ($scenario in $script:Scenarios) {
                $content | Should -Match [regex]::Escape("SCENARIO: $($scenario.Name)")
            }
        }
    }
}
