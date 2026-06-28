#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Unit tests for the TestResultsAggregator module.

    These tests follow red/green TDD: each capability was driven by a failing
    test written before the implementation existed. The tests are fully
    self-contained -- every test that needs input data writes its own temporary
    fixture files in a BeforeAll/BeforeEach block, so the suite is deterministic
    and never depends on (or is disturbed by) the shipped sample fixtures or the
    CI harness that overwrites them.
#>

BeforeAll {
    # Import the module under test relative to this test file's location.
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'TestResultsAggregator.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertFrom-JUnitXml' {

    It 'parses a single passing testcase into a normalized result object' {
        # Arrange: a minimal JUnit document with one passing test.
        $xml = @'
<testsuites>
  <testsuite name="CalcSuite" tests="1" failures="0" skipped="0" time="0.10">
    <testcase name="add" classname="Calc" time="0.10" />
  </testsuite>
</testsuites>
'@
        $path = Join-Path $TestDrive 'one-pass.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        # Act
        $result = ConvertFrom-JUnitXml -Path $path

        # Assert
        $result | Should -HaveCount 1
        $result[0].Name     | Should -BeExactly 'Calc.add'
        $result[0].Status   | Should -BeExactly 'Passed'
        $result[0].Duration | Should -Be 0.10
        $result[0].Suite    | Should -BeExactly 'CalcSuite'
    }

    It 'classifies <failure>, <error> and <skipped> children correctly' {
        $xml = @'
<testsuites>
  <testsuite name="Mixed" tests="4" failures="1" errors="1" skipped="1" time="0.4">
    <testcase name="ok"      classname="T" time="0.1" />
    <testcase name="bad"     classname="T" time="0.1"><failure message="boom" /></testcase>
    <testcase name="crashed" classname="T" time="0.1"><error message="kaboom" /></testcase>
    <testcase name="later"   classname="T" time="0.1"><skipped /></testcase>
  </testsuite>
</testsuites>
'@
        $path = Join-Path $TestDrive 'mixed.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $result = ConvertFrom-JUnitXml -Path $path

        ($result | Where-Object Name -eq 'T.ok').Status      | Should -BeExactly 'Passed'
        ($result | Where-Object Name -eq 'T.bad').Status     | Should -BeExactly 'Failed'
        ($result | Where-Object Name -eq 'T.crashed').Status | Should -BeExactly 'Failed'
        ($result | Where-Object Name -eq 'T.later').Status   | Should -BeExactly 'Skipped'
    }

    It 'handles a standalone <testsuite> root (no <testsuites> wrapper)' {
        $xml = @'
<testsuite name="Solo" tests="1" failures="0" time="0.2">
  <testcase name="works" classname="S" time="0.2" />
</testsuite>
'@
        $path = Join-Path $TestDrive 'solo.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $result = ConvertFrom-JUnitXml -Path $path
        $result | Should -HaveCount 1
        $result[0].Suite | Should -BeExactly 'Solo'
    }

    It 'throws a clear error when the file does not exist' {
        { ConvertFrom-JUnitXml -Path (Join-Path $TestDrive 'nope.xml') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a clear error when the document is not a JUnit report' {
        $path = Join-Path $TestDrive 'notjunit.xml'
        Set-Content -Path $path -Value '<rootonly />' -Encoding utf8
        { ConvertFrom-JUnitXml -Path $path } | Should -Throw -ExpectedMessage '*JUnit*'
    }
}

Describe 'ConvertFrom-TestJson' {

    It 'parses an object with a "tests" array into normalized results' {
        $json = @'
{
  "suite": "ApiSuite",
  "tests": [
    { "name": "Api.login",  "status": "passed",  "duration": 0.30 },
    { "name": "Api.logout", "status": "failed",  "duration": 0.10 },
    { "name": "Api.skip",   "status": "skipped", "duration": 0.00 }
  ]
}
'@
        $path = Join-Path $TestDrive 'results.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $result = ConvertFrom-TestJson -Path $path

        $result | Should -HaveCount 3
        ($result | Where-Object Name -eq 'Api.login').Status   | Should -BeExactly 'Passed'
        ($result | Where-Object Name -eq 'Api.logout').Status  | Should -BeExactly 'Failed'
        ($result | Where-Object Name -eq 'Api.skip').Status    | Should -BeExactly 'Skipped'
        ($result | Where-Object Name -eq 'Api.login').Duration | Should -Be 0.30
        ($result | Where-Object Name -eq 'Api.login').Suite    | Should -BeExactly 'ApiSuite'
    }

    It 'accepts a bare top-level JSON array of tests' {
        $json = '[ { "name": "a", "result": "pass", "time": 1.5 } ]'
        $path = Join-Path $TestDrive 'array.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $result = ConvertFrom-TestJson -Path $path
        $result | Should -HaveCount 1
        $result[0].Name     | Should -BeExactly 'a'
        $result[0].Status   | Should -BeExactly 'Passed'
        $result[0].Duration | Should -Be 1.5
    }

    It 'throws a clear error on malformed JSON' {
        $path = Join-Path $TestDrive 'broken.json'
        Set-Content -Path $path -Value '{ not valid json' -Encoding utf8
        { ConvertFrom-TestJson -Path $path } | Should -Throw -ExpectedMessage '*JSON*'
    }
}

Describe 'Import-TestResultFile' {

    It 'dispatches .xml files to the JUnit parser and tags the run source' {
        $xml = @'
<testsuite name="S" tests="1" time="0.1"><testcase name="t" classname="C" time="0.1" /></testsuite>
'@
        $path = Join-Path $TestDrive 'run-a.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $result = Import-TestResultFile -Path $path
        $result | Should -HaveCount 1
        $result[0].Name | Should -BeExactly 'C.t'
        # The Run column lets aggregation distinguish matrix legs.
        $result[0].Run  | Should -BeExactly 'run-a.xml'
    }

    It 'dispatches .json files to the JSON parser and tags the run source' {
        $json = '{ "tests": [ { "name": "x", "status": "passed", "duration": 0.5 } ] }'
        $path = Join-Path $TestDrive 'run-b.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $result = Import-TestResultFile -Path $path
        $result[0].Run | Should -BeExactly 'run-b.json'
    }

    It 'throws a clear error for an unsupported file extension' {
        $path = Join-Path $TestDrive 'data.txt'
        Set-Content -Path $path -Value 'nope' -Encoding utf8
        { Import-TestResultFile -Path $path } | Should -Throw -ExpectedMessage '*Unsupported*'
    }
}

Describe 'Get-TestTotals' {

    BeforeAll {
        # A small set spanning all three statuses across two runs.
        $script:sample = @(
            [pscustomobject]@{ Name = 'A.one';   Status = 'Passed';  Duration = 0.10; Run = 'r1' }
            [pscustomobject]@{ Name = 'A.two';   Status = 'Failed';  Duration = 0.20; Run = 'r1' }
            [pscustomobject]@{ Name = 'A.three'; Status = 'Skipped'; Duration = 0.00; Run = 'r1' }
            [pscustomobject]@{ Name = 'A.one';   Status = 'Passed';  Duration = 0.15; Run = 'r2' }
            [pscustomobject]@{ Name = 'A.two';   Status = 'Passed';  Duration = 0.25; Run = 'r2' }
        )
    }

    It 'counts passed, failed, skipped and total result instances' {
        $totals = Get-TestTotals -Result $script:sample
        $totals.Passed  | Should -Be 3
        $totals.Failed  | Should -Be 1
        $totals.Skipped | Should -Be 1
        $totals.Total   | Should -Be 5
    }

    It 'sums the duration across all result instances' {
        $totals = Get-TestTotals -Result $script:sample
        $totals.Duration | Should -Be 0.70
    }

    It 'returns all-zero totals for an empty result set' {
        $totals = Get-TestTotals -Result @()
        $totals.Total    | Should -Be 0
        $totals.Duration | Should -Be 0
    }
}

Describe 'Get-FlakyTest' {

    It 'flags a test that passed in one run and failed in another' {
        $results = @(
            [pscustomobject]@{ Name = 'Calc.divide'; Status = 'Failed'; Duration = 0.05; Run = 'r1' }
            [pscustomobject]@{ Name = 'Calc.divide'; Status = 'Passed'; Duration = 0.06; Run = 'r2' }
        )
        $flaky = @(Get-FlakyTest -Result $results)
        $flaky | Should -HaveCount 1
        $flaky[0].Name        | Should -BeExactly 'Calc.divide'
        $flaky[0].PassedCount | Should -Be 1
        $flaky[0].FailedCount | Should -Be 1
    }

    It 'does NOT flag a test that failed in every run (stable failure)' {
        $results = @(
            [pscustomobject]@{ Name = 'Api.broken'; Status = 'Failed'; Duration = 0.05; Run = 'r1' }
            [pscustomobject]@{ Name = 'Api.broken'; Status = 'Failed'; Duration = 0.04; Run = 'r2' }
        )
        Get-FlakyTest -Result $results | Should -BeNullOrEmpty
    }

    It 'does NOT flag a test that passed in every run' {
        $results = @(
            [pscustomobject]@{ Name = 'Api.ok'; Status = 'Passed'; Duration = 0.05; Run = 'r1' }
            [pscustomobject]@{ Name = 'Api.ok'; Status = 'Passed'; Duration = 0.04; Run = 'r2' }
        )
        Get-FlakyTest -Result $results | Should -BeNullOrEmpty
    }

    It 'treats a pass-then-skip as non-flaky (skip is not a failure)' {
        $results = @(
            [pscustomobject]@{ Name = 'X.maybe'; Status = 'Passed';  Duration = 0.05; Run = 'r1' }
            [pscustomobject]@{ Name = 'X.maybe'; Status = 'Skipped'; Duration = 0.00; Run = 'r2' }
        )
        Get-FlakyTest -Result $results | Should -BeNullOrEmpty
    }

    It 'returns flaky tests sorted by name when several are present' {
        $results = @(
            [pscustomobject]@{ Name = 'Zeta.t';  Status = 'Passed'; Duration = 0; Run = 'r1' }
            [pscustomobject]@{ Name = 'Zeta.t';  Status = 'Failed'; Duration = 0; Run = 'r2' }
            [pscustomobject]@{ Name = 'Alpha.t'; Status = 'Failed'; Duration = 0; Run = 'r1' }
            [pscustomobject]@{ Name = 'Alpha.t'; Status = 'Passed'; Duration = 0; Run = 'r2' }
        )
        $flaky = @(Get-FlakyTest -Result $results)
        $flaky | Should -HaveCount 2
        $flaky[0].Name | Should -BeExactly 'Alpha.t'
        $flaky[1].Name | Should -BeExactly 'Zeta.t'
    }
}

Describe 'New-TestSummaryMarkdown' {

    BeforeAll {
        $script:flakyResults = @(
            [pscustomobject]@{ Name = 'Calc.add';    Status = 'Passed';  Duration = 0.10; Suite = 'Calc'; Run = 'run1-junit.xml' }
            [pscustomobject]@{ Name = 'Calc.divide'; Status = 'Failed';  Duration = 0.05; Suite = 'Calc'; Run = 'run1-junit.xml' }
            [pscustomobject]@{ Name = 'Calc.legacy'; Status = 'Skipped'; Duration = 0.00; Suite = 'Calc'; Run = 'run1-junit.xml' }
            [pscustomobject]@{ Name = 'Calc.add';    Status = 'Passed';  Duration = 0.12; Suite = 'Calc'; Run = 'run2-results.json' }
            [pscustomobject]@{ Name = 'Calc.divide'; Status = 'Passed';  Duration = 0.06; Suite = 'Calc'; Run = 'run2-results.json' }
        )
    }

    It 'renders a heading and a totals table' {
        $md = New-TestSummaryMarkdown -Result $script:flakyResults
        $md | Should -Match '# Test Results Summary'
        $md | Should -Match '\| *Passed *\| *3 *\|'
        $md | Should -Match '\| *Failed *\| *1 *\|'
        $md | Should -Match '\| *Skipped *\| *1 *\|'
    }

    It 'reports the total duration in seconds and the number of runs aggregated' {
        $md = New-TestSummaryMarkdown -Result $script:flakyResults
        $md | Should -Match '0\.33s'   # 0.10+0.05+0.00+0.12+0.06
        $md | Should -Match 'Runs aggregated.*2'
    }

    It 'lists flaky tests by name with their pass/fail counts' {
        $md = New-TestSummaryMarkdown -Result $script:flakyResults
        $md | Should -Match '## Flaky Tests'
        $md | Should -Match 'Calc\.divide'
    }

    It 'states clearly when there are no flaky tests' {
        $clean = @(
            [pscustomobject]@{ Name = 'A.t'; Status = 'Passed'; Duration = 0.1; Suite = 'A'; Run = 'r1' }
            [pscustomobject]@{ Name = 'A.t'; Status = 'Passed'; Duration = 0.1; Suite = 'A'; Run = 'r2' }
        )
        $md = New-TestSummaryMarkdown -Result $clean
        $md | Should -Match 'No flaky tests detected'
        $md | Should -Not -Match 'A\.t.*\|.*\|'   # no flaky table row for it
    }
}

Describe 'Invoke-TestResultAggregation' {

    BeforeAll {
        # Build a two-leg matrix in a temp directory: a JUnit leg and a JSON leg
        # of the SAME suite, with one genuinely flaky test (Calc.divide).
        $script:inputDir = Join-Path $TestDrive 'matrix'
        New-Item -ItemType Directory -Path $script:inputDir | Out-Null

        $junit = @'
<testsuites>
  <testsuite name="Calc" tests="4" failures="1" skipped="1" time="0.35">
    <testcase name="add"      classname="Calc" time="0.10" />
    <testcase name="subtract" classname="Calc" time="0.20" />
    <testcase name="divide"   classname="Calc" time="0.05"><failure message="div0" /></testcase>
    <testcase name="legacy"   classname="Calc" time="0.00"><skipped /></testcase>
  </testsuite>
</testsuites>
'@
        Set-Content -Path (Join-Path $script:inputDir 'run1-junit.xml') -Value $junit -Encoding utf8

        $json = @'
{
  "suite": "Calc",
  "tests": [
    { "name": "Calc.add",      "status": "passed",  "duration": 0.12 },
    { "name": "Calc.subtract", "status": "passed",  "duration": 0.18 },
    { "name": "Calc.divide",   "status": "passed",  "duration": 0.06 },
    { "name": "Calc.legacy",   "status": "skipped", "duration": 0.00 }
  ]
}
'@
        Set-Content -Path (Join-Path $script:inputDir 'run2-results.json') -Value $json -Encoding utf8
    }

    It 'aggregates every .xml and .json file in a directory' {
        $report = Invoke-TestResultAggregation -Path $script:inputDir
        $report.Totals.Passed  | Should -Be 5   # add,subtract (r1) + add,subtract,divide (r2)
        $report.Totals.Failed  | Should -Be 1   # divide (r1)
        $report.Totals.Skipped | Should -Be 2   # legacy x2
        $report.Totals.Total   | Should -Be 8
        $report.Totals.Duration | Should -Be 0.71
        $report.RunCount       | Should -Be 2
    }

    It 'detects the flaky test across the two legs' {
        $report = Invoke-TestResultAggregation -Path $script:inputDir
        $report.Flaky | Should -HaveCount 1
        $report.Flaky[0].Name | Should -BeExactly 'Calc.divide'
    }

    It 'includes a rendered Markdown summary' {
        $report = Invoke-TestResultAggregation -Path $script:inputDir
        $report.Markdown | Should -Match '# Test Results Summary'
        $report.Markdown | Should -Match 'Calc\.divide'
    }

    It 'accepts an explicit list of files as well as a directory' {
        $files = @(
            (Join-Path $script:inputDir 'run1-junit.xml')
            (Join-Path $script:inputDir 'run2-results.json')
        )
        $report = Invoke-TestResultAggregation -Path $files
        $report.Totals.Total | Should -Be 8
    }

    It 'throws a clear error when the directory contains no test files' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Invoke-TestResultAggregation -Path $empty } |
            Should -Throw -ExpectedMessage '*No test result files*'
    }
}
