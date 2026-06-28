# Pester unit tests for the Test Results Aggregator module.
#
# These tests drive the design of TestResultsAggregator.psm1 using red/green TDD.
# Each Describe block targets one public function. We build fixtures inline (in a
# per-test temp directory) so the tests are hermetic and runnable anywhere.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the Tests/ directory.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TestResultsAggregator.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertFrom-JUnitXml' {
    It 'parses a JUnit XML file into normalized test case records' {
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="MathSuite" tests="3" failures="1" skipped="1" time="1.5">
    <testcase classname="MathSuite" name="adds" time="0.50"/>
    <testcase classname="MathSuite" name="subtracts" time="0.25">
      <failure message="expected 1 got 2">boom</failure>
    </testcase>
    <testcase classname="MathSuite" name="divides" time="0.75">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>
'@
        $path = Join-Path $TestDrive 'results.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $cases = ConvertFrom-JUnitXml -Path $path

        $cases.Count | Should -Be 3
        ($cases | Where-Object Name -eq 'adds').Status      | Should -Be 'Passed'
        ($cases | Where-Object Name -eq 'subtracts').Status | Should -Be 'Failed'
        ($cases | Where-Object Name -eq 'divides').Status   | Should -Be 'Skipped'
        ($cases | Where-Object Name -eq 'adds').Suite       | Should -Be 'MathSuite'
        ($cases | Where-Object Name -eq 'adds').Duration    | Should -Be 0.50
    }

    It 'throws a meaningful error when the file does not exist' {
        { ConvertFrom-JUnitXml -Path (Join-Path $TestDrive 'nope.xml') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error on malformed XML' {
        $path = Join-Path $TestDrive 'bad.xml'
        Set-Content -Path $path -Value '<testsuites><oops>' -Encoding utf8
        { ConvertFrom-JUnitXml -Path $path } | Should -Throw '*XML*'
    }
}

Describe 'ConvertFrom-TestJson' {
    It 'parses a JSON file with a tests array into normalized records' {
        $json = @'
{
  "name": "ApiSuite",
  "tests": [
    { "name": "login",  "suite": "ApiSuite", "status": "passed",  "duration": 1.2 },
    { "name": "logout", "suite": "ApiSuite", "status": "failed",  "duration": 0.8 },
    { "name": "refresh","suite": "ApiSuite", "status": "skipped", "duration": 0.0 }
  ]
}
'@
        $path = Join-Path $TestDrive 'results.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $cases = ConvertFrom-TestJson -Path $path

        $cases.Count | Should -Be 3
        ($cases | Where-Object Name -eq 'login').Status     | Should -Be 'Passed'
        ($cases | Where-Object Name -eq 'logout').Status    | Should -Be 'Failed'
        ($cases | Where-Object Name -eq 'refresh').Status   | Should -Be 'Skipped'
        ($cases | Where-Object Name -eq 'login').Duration   | Should -Be 1.2
        ($cases | Where-Object Name -eq 'login').Suite      | Should -Be 'ApiSuite'
    }

    It 'accepts a bare top-level array of test cases' {
        $json = '[{ "name": "a", "status": "ok", "duration": 0.1 }]'
        $path = Join-Path $TestDrive 'bare.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $cases = ConvertFrom-TestJson -Path $path
        $cases.Count | Should -Be 1
        $cases[0].Status | Should -Be 'Passed'
    }
}

Describe 'Import-TestResults' {
    BeforeEach {
        # Two runs of the same suite (a matrix build), spread across formats.
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:dir | Out-Null

        @'
<testsuites><testsuite name="S" tests="2" failures="0" time="1.0">
  <testcase classname="S" name="alpha" time="0.5"/>
  <testcase classname="S" name="flaky" time="0.5"/>
</testsuite></testsuites>
'@ | Set-Content -Path (Join-Path $script:dir 'run1.xml') -Encoding utf8

        @'
{ "name": "S", "tests": [
  { "name": "alpha", "suite": "S", "status": "passed", "duration": 0.4 },
  { "name": "flaky", "suite": "S", "status": "failed", "duration": 0.6 }
] }
'@ | Set-Content -Path (Join-Path $script:dir 'run2.json') -Encoding utf8
    }

    It 'dispatches by file extension and tags each record with its source file' {
        $cases = Import-TestResults -Path $script:dir
        $cases.Count | Should -Be 4
        ($cases | Select-Object -ExpandProperty File -Unique).Count | Should -Be 2
    }

    It 'ignores files with unsupported extensions' {
        'noise' | Set-Content -Path (Join-Path $script:dir 'README.txt') -Encoding utf8
        $cases = Import-TestResults -Path $script:dir
        $cases.Count | Should -Be 4
    }

    It 'throws when the directory has no supported result files' {
        $empty = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Import-TestResults -Path $empty } | Should -Throw '*no * result files*'
    }
}

Describe 'Get-TestAggregate' {
    BeforeAll {
        # Three matrix runs. 'flaky' passes in run1/run3 but fails in run2.
        # 'stable' always passes. 'gone' is skipped once.
        $script:records = @(
            [pscustomobject]@{ Suite='S'; Name='stable'; Status='Passed';  Duration=0.5; File='run1.xml' }
            [pscustomobject]@{ Suite='S'; Name='flaky';  Status='Passed';  Duration=0.5; File='run1.xml' }
            [pscustomobject]@{ Suite='S'; Name='gone';   Status='Skipped'; Duration=0.0; File='run1.xml' }
            [pscustomobject]@{ Suite='S'; Name='stable'; Status='Passed';  Duration=0.5; File='run2.json' }
            [pscustomobject]@{ Suite='S'; Name='flaky';  Status='Failed';  Duration=0.7; File='run2.json' }
            [pscustomobject]@{ Suite='S'; Name='stable'; Status='Passed';  Duration=0.5; File='run3.xml' }
            [pscustomobject]@{ Suite='S'; Name='flaky';  Status='Passed';  Duration=0.6; File='run3.xml' }
        )
        $script:agg = Get-TestAggregate -Records $script:records
    }

    It 'counts totals across every run' {
        $script:agg.Total   | Should -Be 7
        $script:agg.Passed  | Should -Be 5
        $script:agg.Failed  | Should -Be 1
        $script:agg.Skipped | Should -Be 1
    }

    It 'sums total duration across every run' {
        # 0.5 + 0.5 + 0.0 + 0.5 + 0.7 + 0.5 + 0.6 = 3.3
        $script:agg.Duration | Should -Be 3.3
    }

    It 'reports the number of distinct source files (matrix runs)' {
        $script:agg.RunCount | Should -Be 3
    }

    It 'identifies only tests that both passed and failed as flaky' {
        $script:agg.Flaky.Count | Should -Be 1
        $script:agg.Flaky[0].Name | Should -Be 'flaky'
        $script:agg.Flaky[0].Suite | Should -Be 'S'
        # The flaky entry records how often it passed vs failed.
        $script:agg.Flaky[0].PassCount | Should -Be 2
        $script:agg.Flaky[0].FailCount | Should -Be 1
    }

    It 'returns an empty flaky list when no test ever flips' {
        $stableOnly = $script:records | Where-Object Name -ne 'flaky'
        (Get-TestAggregate -Records $stableOnly).Flaky.Count | Should -Be 0
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $script:agg = [pscustomobject]@{
            Total=7; Passed=5; Failed=1; Skipped=1; Duration=3.3; RunCount=3
            Flaky=@([pscustomobject]@{ Suite='S'; Name='flaky'; PassCount=2; FailCount=1 })
        }
        $script:md = New-MarkdownSummary -Aggregate $script:agg
    }

    It 'renders a heading and a totals table with exact values' {
        $script:md | Should -Match '# Test Results Summary'
        $script:md | Should -Match '\| Passed \| 5 \|'
        $script:md | Should -Match '\| Failed \| 1 \|'
        $script:md | Should -Match '\| Skipped \| 1 \|'
        $script:md | Should -Match '\| Total \| 7 \|'
        $script:md | Should -Match '\| Duration \| 3.3s \|'
        $script:md | Should -Match '\| Runs \| 3 \|'
    }

    It 'includes a flaky tests section listing each flaky test' {
        $script:md | Should -Match '## Flaky Tests'
        $script:md | Should -Match '\| S \| flaky \| 2 \| 1 \|'
    }

    It 'reports a green status line when there are no failures or flakes' {
        $clean = [pscustomobject]@{
            Total=2; Passed=2; Failed=0; Skipped=0; Duration=1.0; RunCount=1; Flaky=@()
        }
        $md = New-MarkdownSummary -Aggregate $clean
        $md | Should -Match 'No flaky tests detected'
        $md | Should -Match 'All 2 tests passed'
    }
}

Describe 'Invoke-Aggregator.ps1 (CLI entry point)' {
    BeforeAll {
        $script:Cli = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-Aggregator.ps1'
    }

    BeforeEach {
        $script:inDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:inDir | Out-Null
        @'
<testsuites><testsuite name="S" tests="2" failures="0" time="1.0">
  <testcase classname="S" name="a" time="0.5"/>
  <testcase classname="S" name="flaky" time="0.5"/>
</testsuite></testsuites>
'@ | Set-Content -Path (Join-Path $script:inDir 'r1.xml') -Encoding utf8
        @'
{ "name":"S","tests":[
  {"name":"a","suite":"S","status":"passed","duration":0.5},
  {"name":"flaky","suite":"S","status":"failed","duration":0.5}
]}
'@ | Set-Content -Path (Join-Path $script:inDir 'r2.json') -Encoding utf8
    }

    It 'prints the markdown summary to stdout with exact totals' {
        $out = pwsh -NoProfile -File $script:Cli -Path $script:inDir
        $text = $out -join "`n"
        $text | Should -Match '\| Total \| 4 \|'
        $text | Should -Match '\| Failed \| 1 \|'
        $text | Should -Match '\| S \| flaky \| 1 \| 1 \|'
    }

    It 'writes the summary to the file named by GITHUB_STEP_SUMMARY' {
        $summary = Join-Path $TestDrive 'step-summary.md'
        $env:GITHUB_STEP_SUMMARY = $summary
        try {
            pwsh -NoProfile -File $script:Cli -Path $script:inDir | Out-Null
        }
        finally {
            $env:GITHUB_STEP_SUMMARY = $null
        }
        (Test-Path $summary) | Should -BeTrue
        (Get-Content $summary -Raw) | Should -Match '# Test Results Summary'
    }

    It 'exits 0 by default even when some tests failed (it is a reporter)' {
        pwsh -NoProfile -File $script:Cli -Path $script:inDir | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 on test failures when -FailOnFailure is given (build gate)' {
        pwsh -NoProfile -File $script:Cli -Path $script:inDir -FailOnFailure 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 2 with a clear error when the path is empty of results' {
        $empty = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $empty | Out-Null
        pwsh -NoProfile -File $script:Cli -Path $empty 2>$null
        $LASTEXITCODE | Should -Be 2
    }
}
