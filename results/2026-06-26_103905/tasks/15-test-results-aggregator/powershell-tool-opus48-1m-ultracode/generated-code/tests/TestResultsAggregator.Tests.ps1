# Unit tests for the Test Results Aggregator module.
#
# These follow red/green TDD: each capability was driven out by a failing test
# before the corresponding function existed in TestResultsAggregator.psm1.
#
# The module produces a *normalized* test-result object for every test case it
# reads, regardless of input format (JUnit XML or JSON). That normalized shape
# is the contract every other function (totals, flaky detection, markdown) is
# built on, so it is the first thing exercised here.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'TestResultsAggregator.psm1'
    Import-Module $script:ModulePath -Force

    # A scratch directory where each test can drop the exact fixture content it
    # needs. Keeping fixtures inline (rather than shared on disk) makes every
    # expectation self-contained and impossible to break from another test.
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("tra-unit-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:Work) { Remove-Item $script:Work -Recurse -Force }
}

Describe 'ConvertFrom-JUnitXml' {

    It 'normalizes passed, failed, and skipped JUnit test cases' {
        $xml = @'
<testsuites>
  <testsuite name="Math" tests="3" failures="1" skipped="1" time="0.30">
    <testcase classname="Math" name="adds" time="0.10"/>
    <testcase classname="Math" name="divides" time="0.10">
      <failure message="boom">stack trace</failure>
    </testcase>
    <testcase classname="Math" name="modulo" time="0.10">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>
'@
        $path = Join-Path $script:Work 'junit-basic.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $results = ConvertFrom-JUnitXml -Path $path

        $results.Count | Should -Be 3
        ($results | Where-Object Name -eq 'adds').Status    | Should -Be 'passed'
        ($results | Where-Object Name -eq 'divides').Status | Should -Be 'failed'
        ($results | Where-Object Name -eq 'modulo').Status  | Should -Be 'skipped'
        ($results | Where-Object Name -eq 'adds').Suite     | Should -Be 'Math'
        ($results | Where-Object Name -eq 'adds').Duration  | Should -Be 0.10
    }

    It 'treats an <error> child as failed and accepts a bare <testsuite> root' {
        # Many tools emit a single <testsuite> as the document root (no
        # <testsuites> wrapper) and report crashes as <error> rather than <failure>.
        $xml = @'
<testsuite name="Suite" tests="2" failures="0" errors="1" time="0.20">
  <testcase classname="Suite" name="ok" time="0.10"/>
  <testcase classname="Suite" name="crashes" time="0.10">
    <error message="kaboom">trace</error>
  </testcase>
</testsuite>
'@
        $path = Join-Path $script:Work 'junit-error.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        $results = ConvertFrom-JUnitXml -Path $path
        $results.Count | Should -Be 2
        ($results | Where-Object Name -eq 'crashes').Status | Should -Be 'failed'
        ($results | Where-Object Name -eq 'ok').Status      | Should -Be 'passed'
    }

    It 'falls back to the <testsuite> name when classname is absent' {
        $xml = '<testsuites><testsuite name="FallbackSuite"><testcase name="t" time="1"/></testsuite></testsuites>'
        $path = Join-Path $script:Work 'junit-noclass.xml'
        Set-Content -Path $path -Value $xml -Encoding utf8

        (ConvertFrom-JUnitXml -Path $path)[0].Suite | Should -Be 'FallbackSuite'
    }

    It 'throws a clear error when the file does not exist' {
        { ConvertFrom-JUnitXml -Path (Join-Path $script:Work 'nope.xml') } |
            Should -Throw '*not found*'
    }
}

Describe 'ConvertFrom-TestJson' {

    It 'normalizes an object with a tests array and a document-level suite' {
        $json = @'
{
  "suite": "Math",
  "tests": [
    { "name": "adds", "status": "passed", "duration": 0.12 },
    { "name": "divides", "status": "failed", "duration": 0.13 },
    { "name": "modulo", "status": "skipped" }
  ]
}
'@
        $path = Join-Path $script:Work 'results.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $results = ConvertFrom-TestJson -Path $path
        $results.Count | Should -Be 3
        ($results | Where-Object Name -eq 'adds').Status     | Should -Be 'passed'
        ($results | Where-Object Name -eq 'adds').Suite      | Should -Be 'Math'
        ($results | Where-Object Name -eq 'divides').Status  | Should -Be 'failed'
        ($results | Where-Object Name -eq 'modulo').Status   | Should -Be 'skipped'
        # Missing duration defaults to 0.
        ($results | Where-Object Name -eq 'modulo').Duration | Should -Be 0
    }

    It 'normalizes status synonyms (pass/FAIL/Skip) case-insensitively' {
        $json = '[{"name":"a","suite":"S","status":"PASS"},{"name":"b","suite":"S","status":"Fail"},{"name":"c","suite":"S","status":"Skip"}]'
        $path = Join-Path $script:Work 'synonyms.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        $results = ConvertFrom-TestJson -Path $path
        ($results | Where-Object Name -eq 'a').Status | Should -Be 'passed'
        ($results | Where-Object Name -eq 'b').Status | Should -Be 'failed'
        ($results | Where-Object Name -eq 'c').Status | Should -Be 'skipped'
    }

    It 'lets a per-case suite override the document-level suite' {
        $json = '{"suite":"Default","tests":[{"name":"t","status":"passed","suite":"Override"}]}'
        $path = Join-Path $script:Work 'override.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        (ConvertFrom-TestJson -Path $path)[0].Suite | Should -Be 'Override'
    }

    It 'throws when a test case is missing required fields' {
        $json = '{"tests":[{"name":"t"}]}'
        $path = Join-Path $script:Work 'bad.json'
        Set-Content -Path $path -Value $json -Encoding utf8

        { ConvertFrom-TestJson -Path $path } | Should -Throw "*no 'status' field*"
    }

    It 'throws on an unrecognized status value' {
        { ConvertTo-CanonicalStatus -Status 'bogus' } | Should -Throw '*Unrecognized test status*'
    }
}

Describe 'Import-TestResultFile' {

    It 'dispatches to the JUnit parser for .xml files' {
        $path = Join-Path $script:Work 'dispatch.xml'
        Set-Content -Path $path -Value '<testsuite name="S"><testcase classname="S" name="t" time="1"/></testsuite>' -Encoding utf8
        (Import-TestResultFile -Path $path)[0].Name | Should -Be 't'
    }

    It 'dispatches to the JSON parser for .json files' {
        $path = Join-Path $script:Work 'dispatch.json'
        Set-Content -Path $path -Value '{"suite":"S","tests":[{"name":"t","status":"passed"}]}' -Encoding utf8
        (Import-TestResultFile -Path $path)[0].Name | Should -Be 't'
    }

    It 'throws for an unsupported extension' {
        $path = Join-Path $script:Work 'data.txt'
        Set-Content -Path $path -Value 'nope' -Encoding utf8
        { Import-TestResultFile -Path $path } | Should -Throw '*Unsupported test result format*'
    }
}

Describe 'Get-TestResultSummary' {

    It 'counts passed/failed/skipped and sums duration' {
        $results = @(
            New-Object psobject -Property @{ Suite='S'; Name='a'; Status='passed';  Duration=0.5 }
            New-Object psobject -Property @{ Suite='S'; Name='b'; Status='failed';  Duration=0.25 }
            New-Object psobject -Property @{ Suite='S'; Name='c'; Status='skipped'; Duration=0.0 }
            New-Object psobject -Property @{ Suite='S'; Name='d'; Status='passed';  Duration=0.25 }
        )
        $summary = Get-TestResultSummary -Results $results
        $summary.Total    | Should -Be 4
        $summary.Passed   | Should -Be 2
        $summary.Failed   | Should -Be 1
        $summary.Skipped  | Should -Be 1
        $summary.Duration | Should -Be 1.0
    }
}

Describe 'Get-FlakyTest' {

    It 'flags a test that both passed and failed across runs' {
        # "Math::divides" passes once and fails once -> flaky.
        # "Math::adds" always passes -> stable. "Math::modulo" only skips -> stable.
        $results = @(
            New-Object psobject -Property @{ Suite='Math'; Name='divides'; Status='failed';  Duration=0.1 }
            New-Object psobject -Property @{ Suite='Math'; Name='divides'; Status='passed';  Duration=0.1 }
            New-Object psobject -Property @{ Suite='Math'; Name='adds';    Status='passed';  Duration=0.1 }
            New-Object psobject -Property @{ Suite='Math'; Name='adds';    Status='passed';  Duration=0.1 }
            New-Object psobject -Property @{ Suite='Math'; Name='modulo';  Status='skipped'; Duration=0.0 }
        )
        $flaky = Get-FlakyTest -Results $results
        $flaky.Count       | Should -Be 1
        $flaky[0].Key      | Should -Be 'Math::divides'
        $flaky[0].Passed   | Should -Be 1
        $flaky[0].Failed   | Should -Be 1
    }

    It 'returns nothing when every test is stable' {
        $results = @(
            New-Object psobject -Property @{ Suite='S'; Name='a'; Status='passed'; Duration=0.1 }
            New-Object psobject -Property @{ Suite='S'; Name='a'; Status='passed'; Duration=0.1 }
        )
        (Get-FlakyTest -Results $results).Count | Should -Be 0
    }
}

Describe 'Get-AggregatedTestResults (matrix aggregation)' {

    BeforeAll {
        # Two "matrix runs": run1 is JUnit XML, run2 is JSON. 'divides' fails in
        # run1 and passes in run2 -> the canonical flaky case.
        $script:AggDir = Join-Path $script:Work 'agg'
        New-Item -ItemType Directory -Path $script:AggDir -Force | Out-Null

        Set-Content -Path (Join-Path $script:AggDir 'run1.xml') -Encoding utf8 -Value @'
<testsuites>
  <testsuite name="Math" tests="3" failures="1" time="0.30">
    <testcase classname="Math" name="adds" time="0.10"/>
    <testcase classname="Math" name="subtracts" time="0.10"/>
    <testcase classname="Math" name="divides" time="0.10"><failure message="boom">x</failure></testcase>
  </testsuite>
</testsuites>
'@
        Set-Content -Path (Join-Path $script:AggDir 'run2.json') -Encoding utf8 -Value @'
{ "suite": "Math", "tests": [
  { "name": "adds", "status": "passed", "duration": 0.12 },
  { "name": "subtracts", "status": "passed", "duration": 0.11 },
  { "name": "divides", "status": "passed", "duration": 0.13 },
  { "name": "modulo", "status": "skipped", "duration": 0.0 }
] }
'@
        $script:Agg = Get-AggregatedTestResults -Path $script:AggDir
    }

    It 'aggregates totals across both formats' {
        $script:Agg.Summary.Total   | Should -Be 7
        $script:Agg.Summary.Passed  | Should -Be 5
        $script:Agg.Summary.Failed  | Should -Be 1
        $script:Agg.Summary.Skipped | Should -Be 1
    }

    It 'sums duration across both formats' {
        # 0.30 (run1) + 0.36 (run2) = 0.66
        [math]::Round($script:Agg.Summary.Duration, 2) | Should -Be 0.66
    }

    It 'identifies the flaky test across the two runs' {
        $script:Agg.Flaky.Count  | Should -Be 1
        $script:Agg.Flaky[0].Key | Should -Be 'Math::divides'
    }

    It 'produces a per-file breakdown with one row per input file' {
        $script:Agg.Files.Count | Should -Be 2
        ($script:Agg.Files | Where-Object File -eq 'run1.xml').Failed | Should -Be 1
        ($script:Agg.Files | Where-Object File -eq 'run2.json').Skipped | Should -Be 1
    }

    It 'throws a clear error when no result files are present' {
        $empty = Join-Path $script:Work 'empty'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        { Get-AggregatedTestResults -Path $empty } | Should -Throw '*No test result files*'
    }
}

Describe 'Format-TestResultMarkdown' {

    BeforeAll {
        $script:MdDir = Join-Path $script:Work 'md'
        New-Item -ItemType Directory -Path $script:MdDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:MdDir 'r1.xml') -Encoding utf8 -Value '<testsuite name="S"><testcase classname="S" name="t" time="1"/><testcase classname="S" name="u" time="1"><failure/></testcase></testsuite>'
        Set-Content -Path (Join-Path $script:MdDir 'r2.json') -Encoding utf8 -Value '{"suite":"S","tests":[{"name":"u","status":"passed","duration":1}]}'
        $script:Md = Format-TestResultMarkdown -Aggregate (Get-AggregatedTestResults -Path $script:MdDir)
    }

    It 'includes a summary heading and totals table' {
        $script:Md | Should -Match '# Test Results Summary'
        $script:Md | Should -Match '\| :white_check_mark: Passed \| 2 \|'
        $script:Md | Should -Match '\| :x: Failed \| 1 \|'
    }

    It 'renders a flaky-tests section listing the flaky test' {
        # 'u' fails in r1.xml and passes in r2.json -> flaky.
        $script:Md | Should -Match '## Flaky Tests'
        $script:Md | Should -Match 'S::u'
    }

    It 'says so explicitly when there are no flaky tests' {
        Set-Content -Path (Join-Path $script:MdDir 'clean.xml') -Encoding utf8 -Value '<testsuite name="C"><testcase classname="C" name="x" time="1"/></testsuite>'
        $clean = Format-TestResultMarkdown -Aggregate (Get-AggregatedTestResults -Path (Join-Path $script:MdDir 'clean.xml'))
        $clean | Should -Match 'No flaky tests detected'
    }
}
