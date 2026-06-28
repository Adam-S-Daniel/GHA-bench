# Unit tests for the Test Results Aggregator module.
#
# Built using red/green TDD: each Describe/Context block below was written as a
# failing test FIRST, then the minimum implementation was added to make it pass.
#
# Run with:  Invoke-Pester -Path tests/TestResultsAggregator.Tests.ps1

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ directory.
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/TestResultsAggregator.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'ConvertFrom-JUnitXml' {

    It 'parses passed, failed and skipped test cases into normalized objects' {
        $xml = @'
<testsuites>
  <testsuite name="MathSuite" tests="3" failures="1" skipped="1" time="1.5">
    <testcase name="adds_numbers" classname="MathSuite" time="0.50"/>
    <testcase name="divides_numbers" classname="MathSuite" time="0.30">
      <failure message="boom">div by zero</failure>
    </testcase>
    <testcase name="todo_feature" classname="MathSuite" time="0.0">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>
'@
        $results = ConvertFrom-JUnitXml -Xml $xml

        $results.Count | Should -Be 3

        $pass = $results | Where-Object Name -eq 'adds_numbers'
        $pass.Status   | Should -Be 'Passed'
        $pass.Suite    | Should -Be 'MathSuite'
        $pass.Duration | Should -Be 0.5

        $fail = $results | Where-Object Name -eq 'divides_numbers'
        $fail.Status | Should -Be 'Failed'

        $skip = $results | Where-Object Name -eq 'todo_feature'
        $skip.Status | Should -Be 'Skipped'
    }

    It 'throws a meaningful error on malformed XML' {
        { ConvertFrom-JUnitXml -Xml '<testsuites><not closed' } |
            Should -Throw -ExpectedMessage '*Failed to parse JUnit XML*'
    }
}

Describe 'ConvertFrom-TestResultJson' {

    It 'parses a JSON document with a tests array into normalized objects' {
        $json = @'
{
  "tests": [
    { "name": "adds_numbers",    "suite": "MathSuite", "status": "passed",  "duration": 0.5 },
    { "name": "divides_numbers", "suite": "MathSuite", "status": "failed",  "duration": 0.3 },
    { "name": "todo_feature",    "suite": "MathSuite", "status": "skipped", "duration": 0.0 }
  ]
}
'@
        $results = ConvertFrom-TestResultJson -Json $json

        $results.Count | Should -Be 3
        ($results | Where-Object Name -eq 'adds_numbers').Status    | Should -Be 'Passed'
        ($results | Where-Object Name -eq 'divides_numbers').Status | Should -Be 'Failed'
        ($results | Where-Object Name -eq 'todo_feature').Status    | Should -Be 'Skipped'
        ($results | Where-Object Name -eq 'adds_numbers').Duration  | Should -Be 0.5
    }

    It 'normalizes assorted status spellings (PASS/fail/ignored)' {
        $json = '{ "tests": [
            { "name": "a", "suite": "S", "status": "PASS",    "duration": 0 },
            { "name": "b", "suite": "S", "status": "fail",    "duration": 0 },
            { "name": "c", "suite": "S", "status": "ignored", "duration": 0 } ] }'
        $results = ConvertFrom-TestResultJson -Json $json
        ($results | Where-Object Name -eq 'a').Status | Should -Be 'Passed'
        ($results | Where-Object Name -eq 'b').Status | Should -Be 'Failed'
        ($results | Where-Object Name -eq 'c').Status | Should -Be 'Skipped'
    }

    It 'throws a meaningful error on malformed JSON' {
        { ConvertFrom-TestResultJson -Json '{ not valid' } |
            Should -Throw -ExpectedMessage '*Failed to parse test result JSON*'
    }
}

Describe 'Import-TestResultFile' {

    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("trf_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tmp | Out-Null

        $script:xmlFile = Join-Path $script:tmp 'a.xml'
        Set-Content -Path $script:xmlFile -Value '<testsuite name="S"><testcase name="t1" classname="S" time="0.1"/></testsuite>'

        $script:jsonFile = Join-Path $script:tmp 'b.json'
        Set-Content -Path $script:jsonFile -Value '{ "tests": [ { "name": "t2", "suite": "S", "status": "failed", "duration": 0.2 } ] }'
    }

    AfterAll {
        Remove-Item -Path $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dispatches .xml files to the JUnit parser' {
        $r = Import-TestResultFile -Path $script:xmlFile
        $r.Count | Should -Be 1
        $r[0].Name   | Should -Be 't1'
        $r[0].Status | Should -Be 'Passed'
    }

    It 'dispatches .json files to the JSON parser' {
        $r = Import-TestResultFile -Path $script:jsonFile
        $r[0].Name   | Should -Be 't2'
        $r[0].Status | Should -Be 'Failed'
    }

    It 'tags each result with its source file name' {
        $r = Import-TestResultFile -Path $script:xmlFile
        $r[0].Source | Should -Be 'a.xml'
    }

    It 'throws a meaningful error for an unsupported extension' {
        $bad = Join-Path $script:tmp 'c.txt'
        Set-Content -Path $bad -Value 'hello'
        { Import-TestResultFile -Path $bad } |
            Should -Throw -ExpectedMessage '*Unsupported test result file type*'
    }

    It 'throws a meaningful error for a missing file' {
        { Import-TestResultFile -Path (Join-Path $script:tmp 'nope.xml') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Import-TestResultDirectory' {

    BeforeAll {
        $script:dir = Join-Path ([System.IO.Path]::GetTempPath()) ("trd_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir | Out-Null
        Set-Content -Path (Join-Path $script:dir 'run1.xml') -Value '<testsuite name="S"><testcase name="t1" classname="S" time="1.0"/></testsuite>'
        Set-Content -Path (Join-Path $script:dir 'run2.json') -Value '{ "tests": [ { "name": "t2", "suite": "S", "status": "passed", "duration": 2.0 } ] }'
    }

    AfterAll {
        Remove-Item -Path $script:dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reads every .xml and .json file in the directory into one combined set' {
        $all = Import-TestResultDirectory -Path $script:dir
        $all.Count | Should -Be 2
        ($all | Where-Object Name -eq 't1') | Should -Not -BeNullOrEmpty
        ($all | Where-Object Name -eq 't2') | Should -Not -BeNullOrEmpty
    }

    It 'throws a meaningful error when no result files are present' {
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("empty_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Import-TestResultDirectory -Path $empty } |
            Should -Throw -ExpectedMessage '*No test result files*'
        Remove-Item $empty -Recurse -Force
    }
}

Describe 'Measure-TestResults' {

    BeforeAll {
        $script:sample = @(
            [PSCustomObject]@{ Name='a'; Suite='S'; Status='Passed';  Duration=1.0 }
            [PSCustomObject]@{ Name='b'; Suite='S'; Status='Failed';  Duration=2.5 }
            [PSCustomObject]@{ Name='c'; Suite='S'; Status='Skipped'; Duration=0.0 }
            [PSCustomObject]@{ Name='d'; Suite='S'; Status='Passed';  Duration=0.5 }
        )
    }

    It 'counts passed, failed, skipped and total' {
        $m = Measure-TestResults -Results $script:sample
        $m.Passed  | Should -Be 2
        $m.Failed  | Should -Be 1
        $m.Skipped | Should -Be 1
        $m.Total   | Should -Be 4
    }

    It 'sums durations across all results' {
        (Measure-TestResults -Results $script:sample).Duration | Should -Be 4.0
    }

    It 'returns all-zero totals for an empty result set' {
        $m = Measure-TestResults -Results @()
        $m.Total    | Should -Be 0
        $m.Duration | Should -Be 0
    }
}

Describe 'Find-FlakyTest' {

    It 'flags a test that passed in one run and failed in another' {
        $results = @(
            [PSCustomObject]@{ Name='login'; Suite='Auth'; Status='Passed'; Duration=1 }
            [PSCustomObject]@{ Name='login'; Suite='Auth'; Status='Failed'; Duration=1 }
            [PSCustomObject]@{ Name='logout'; Suite='Auth'; Status='Passed'; Duration=1 }
        )
        $flaky = @(Find-FlakyTest -Results $results)
        $flaky.Count          | Should -Be 1
        $flaky[0].Name        | Should -Be 'login'
        $flaky[0].Suite       | Should -Be 'Auth'
        $flaky[0].PassedCount | Should -Be 1
        $flaky[0].FailedCount | Should -Be 1
    }

    It 'does not flag a consistently passing or consistently failing test' {
        $results = @(
            [PSCustomObject]@{ Name='stable'; Suite='S'; Status='Passed'; Duration=1 }
            [PSCustomObject]@{ Name='stable'; Suite='S'; Status='Passed'; Duration=1 }
            [PSCustomObject]@{ Name='broken'; Suite='S'; Status='Failed'; Duration=1 }
            [PSCustomObject]@{ Name='broken'; Suite='S'; Status='Failed'; Duration=1 }
        )
        Find-FlakyTest -Results $results | Should -BeNullOrEmpty
    }

    It 'distinguishes same-named tests in different suites' {
        $results = @(
            [PSCustomObject]@{ Name='t'; Suite='A'; Status='Passed'; Duration=1 }
            [PSCustomObject]@{ Name='t'; Suite='A'; Status='Failed'; Duration=1 }
            [PSCustomObject]@{ Name='t'; Suite='B'; Status='Passed'; Duration=1 }
        )
        $flaky = @(Find-FlakyTest -Results $results)
        $flaky.Count   | Should -Be 1
        $flaky[0].Suite | Should -Be 'A'
    }
}

Describe 'New-MarkdownSummary' {

    BeforeAll {
        $script:results = @(
            [PSCustomObject]@{ Name='login';  Suite='Auth'; Status='Passed';  Duration=1.0 }
            [PSCustomObject]@{ Name='login';  Suite='Auth'; Status='Failed';  Duration=1.5 }
            [PSCustomObject]@{ Name='logout'; Suite='Auth'; Status='Passed';  Duration=0.5 }
            [PSCustomObject]@{ Name='todo';   Suite='Auth'; Status='Skipped'; Duration=0.0 }
        )
    }

    It 'renders a heading and a totals table with exact values' {
        $md = New-MarkdownSummary -Results $script:results
        $md | Should -Match '# Test Results Summary'
        $md | Should -Match '\| Passed \| 2 \|'
        $md | Should -Match '\| Failed \| 1 \|'
        $md | Should -Match '\| Skipped \| 1 \|'
        $md | Should -Match '\| Total \| 4 \|'
        $md | Should -Match '\| Duration \| 3.00s \|'
    }

    It 'renders a flaky tests table when flaky tests exist' {
        $md = New-MarkdownSummary -Results $script:results
        $md | Should -Match '## Flaky Tests'
        # Auth/login passed once and failed once -> exactly one flaky row.
        $md | Should -Match '\| Auth \| login \| 1 \| 1 \|'
    }

    It 'states explicitly when there are no flaky tests' {
        $stable = @(
            [PSCustomObject]@{ Name='a'; Suite='S'; Status='Passed'; Duration=1 }
            [PSCustomObject]@{ Name='a'; Suite='S'; Status='Passed'; Duration=1 }
        )
        $md = New-MarkdownSummary -Results $stable
        $md | Should -Match 'No flaky tests detected'
    }
}

Describe 'Invoke-Aggregator.ps1 (CLI entry)' {

    BeforeAll {
        $script:cli = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-Aggregator.ps1'

        $script:fixDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cli_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixDir | Out-Null
        # Two runs of the same suite: 't' is flaky (passed then failed).
        Set-Content -Path (Join-Path $script:fixDir 'run1.xml') -Value '<testsuite name="S"><testcase name="t" classname="S" time="1.0"/><testcase name="u" classname="S" time="0.5"/></testsuite>'
        Set-Content -Path (Join-Path $script:fixDir 'run2.json') -Value '{ "tests": [ { "name": "t", "suite": "S", "status": "failed", "duration": 1.0 } ] }'
    }

    AfterAll {
        Remove-Item -Path $script:fixDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes a markdown summary file and prints it to stdout' {
        $out = Join-Path $script:fixDir 'summary.md'
        $stdout = & $script:cli -InputPath $script:fixDir -OutputPath $out 2>&1 | Out-String

        Test-Path $out | Should -BeTrue
        (Get-Content $out -Raw) | Should -Match '# Test Results Summary'
        $stdout | Should -Match '# Test Results Summary'
        # u(passed) + t(passed) + t(failed) = 2 passed, 1 failed, 3 total
        (Get-Content $out -Raw) | Should -Match '\| Total \| 3 \|'
        (Get-Content $out -Raw) | Should -Match '\| S \| t \| 1 \| 1 \|'
    }

    It 'exits 0 even when some tests failed (it is a reporter, not a gate)' {
        & $script:cli -InputPath $script:fixDir -OutputPath (Join-Path $script:fixDir 's2.md') > $null 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits non-zero with a meaningful error for a missing directory' {
        $err = & $script:cli -InputPath (Join-Path $script:fixDir 'missing') 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $err | Should -Match 'directory not found'
    }
}
