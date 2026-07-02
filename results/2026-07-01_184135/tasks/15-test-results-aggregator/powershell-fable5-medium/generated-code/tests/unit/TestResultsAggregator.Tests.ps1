<#
.SYNOPSIS
    Unit tests for the TestResultsAggregator module (Pester 5).

.DESCRIPTION
    Built with red/green TDD: each Describe block was written as a failing
    test first, then the minimum module code was added to make it pass.

    Fixtures live in tests/fixtures/ so they are independent of the
    top-level fixtures/ directory that the CI workflow aggregates (which
    the act harness swaps out per pipeline test case).
#>

BeforeAll {
    # Import the module under test fresh each run.
    $moduleRoot = Join-Path $PSScriptRoot '..' '..'
    Import-Module (Join-Path $moduleRoot 'TestResultsAggregator.psm1') -Force

    # Fixture directory shared by the unit tests.
    $script:FixtureDir = Join-Path $PSScriptRoot '..' 'fixtures'
}

Describe 'ConvertFrom-JUnitXml' {

    It 'parses passed, failed and skipped test cases from a JUnit XML file' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'run1-junit.xml')

        $results | Should -HaveCount 4

        $alpha = $results | Where-Object Name -eq 'alpha adds numbers'
        $alpha.Result   | Should -Be 'passed'
        $alpha.Suite    | Should -Be 'CalculatorSuite'
        $alpha.Duration | Should -Be 0.5

        ($results | Where-Object Name -eq 'beta divides by zero').Result  | Should -Be 'failed'
        ($results | Where-Object Name -eq 'gamma not implemented').Result | Should -Be 'skipped'
        ($results | Where-Object Name -eq 'flaky network call').Result    | Should -Be 'passed'
    }

    It 'treats <error> elements as failures' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'run-with-error.xml')
        ($results | Where-Object Name -eq 'boom errors out').Result | Should -Be 'failed'
    }

    It 'throws a meaningful error for a missing file' {
        { ConvertFrom-JUnitXml -Path (Join-Path $FixtureDir 'nope.xml') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed XML' {
        $bad = Join-Path $TestDrive 'bad.xml'
        Set-Content -Path $bad -Value '<testsuite><unclosed>'
        { ConvertFrom-JUnitXml -Path $bad } | Should -Throw '*Failed to parse JUnit XML*'
    }
}

Describe 'ConvertFrom-TestResultJson' {

    It 'parses tests from a JSON results file' {
        $results = ConvertFrom-TestResultJson -Path (Join-Path $FixtureDir 'run2-results.json')

        $results | Should -HaveCount 4

        $flaky = $results | Where-Object Name -eq 'flaky network call'
        $flaky.Result   | Should -Be 'failed'
        $flaky.Suite    | Should -Be 'CalculatorSuite'
        $flaky.Duration | Should -Be 1.2

        ($results | Where-Object Name -eq 'alpha adds numbers').Result   | Should -Be 'passed'
        ($results | Where-Object Name -eq 'gamma not implemented').Result | Should -Be 'skipped'
    }

    It 'defaults suite and duration when omitted from a test entry' {
        $json = Join-Path $TestDrive 'minimal.json'
        Set-Content -Path $json -Value '{"tests":[{"name":"lonely test","result":"passed"}]}'

        $r = ConvertFrom-TestResultJson -Path $json
        $r.Suite    | Should -Be '(unnamed suite)'
        $r.Duration | Should -Be 0
    }

    It 'throws a meaningful error for a missing file' {
        { ConvertFrom-TestResultJson -Path (Join-Path $FixtureDir 'nope.json') } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{"tests": [oops'
        { ConvertFrom-TestResultJson -Path $bad } | Should -Throw '*Failed to parse JSON*'
    }

    It 'throws a meaningful error when the "tests" array is missing' {
        $bad = Join-Path $TestDrive 'notests.json'
        Set-Content -Path $bad -Value '{"something":"else"}'
        { ConvertFrom-TestResultJson -Path $bad } | Should -Throw "*does not contain a 'tests' array*"
    }

    It 'throws a meaningful error for an invalid result value' {
        $bad = Join-Path $TestDrive 'badresult.json'
        Set-Content -Path $bad -Value '{"tests":[{"name":"t","result":"exploded"}]}'
        { ConvertFrom-TestResultJson -Path $bad } | Should -Throw '*invalid result*'
    }
}

Describe 'Import-TestResultFile' {

    It 'dispatches .xml files to the JUnit parser' {
        $r = Import-TestResultFile -Path (Join-Path $FixtureDir 'run1-junit.xml')
        $r | Should -HaveCount 4
        $r[0].SourceFile | Should -Be 'run1-junit.xml'
    }

    It 'dispatches .json files to the JSON parser' {
        $r = Import-TestResultFile -Path (Join-Path $FixtureDir 'run2-results.json')
        $r | Should -HaveCount 4
    }

    It 'throws a meaningful error for unsupported extensions' {
        $txt = Join-Path $TestDrive 'results.txt'
        Set-Content -Path $txt -Value 'not a result file'
        { Import-TestResultFile -Path $txt } | Should -Throw '*Unsupported test result format*'
    }
}

Describe 'Get-AggregatedResults' {

    BeforeAll {
        # Two "matrix runs" over the same suite: 'flaky network call'
        # passes in run 1 (XML) and fails in run 2 (JSON).
        $script:AllResults = @(
            Import-TestResultFile -Path (Join-Path $FixtureDir 'run1-junit.xml')
            Import-TestResultFile -Path (Join-Path $FixtureDir 'run2-results.json')
        )
        $script:Agg = Get-AggregatedResults -Results $AllResults
    }

    It 'computes totals across all files' {
        $Agg.Total   | Should -Be 8
        $Agg.Passed  | Should -Be 3
        $Agg.Failed  | Should -Be 3
        $Agg.Skipped | Should -Be 2
    }

    It 'sums durations across all files' {
        # 0.5+0.2+0.0+0.35 (xml) + 0.45+0.25+0.0+1.2 (json) = 2.95
        # Round to tolerate floating-point accumulation error.
        [math]::Round($Agg.Duration, 2) | Should -Be 2.95
    }

    It 'identifies flaky tests (passed in some runs, failed in others)' {
        $Agg.FlakyTests | Should -HaveCount 1
        $Agg.FlakyTests[0].Suite      | Should -Be 'CalculatorSuite'
        $Agg.FlakyTests[0].Name       | Should -Be 'flaky network call'
        $Agg.FlakyTests[0].PassCount  | Should -Be 1
        $Agg.FlakyTests[0].FailCount  | Should -Be 1
    }

    It 'does not mark consistently failing tests as flaky' {
        $Agg.FlakyTests.Name | Should -Not -Contain 'beta divides by zero'
    }

    It 'lists distinct failed tests' {
        # 'beta divides by zero' failed twice but appears once; flaky test also failed.
        $Agg.FailedTests | Should -HaveCount 2
        $Agg.FailedTests.Name | Should -Contain 'beta divides by zero'
        $Agg.FailedTests.Name | Should -Contain 'flaky network call'
    }

    It 'handles an empty result set gracefully' {
        $empty = Get-AggregatedResults -Results @()
        $empty.Total      | Should -Be 0
        $empty.FlakyTests | Should -HaveCount 0
    }
}

Describe 'New-MarkdownSummary' {

    BeforeAll {
        $script:AllResults = @(
            Import-TestResultFile -Path (Join-Path $FixtureDir 'run1-junit.xml')
            Import-TestResultFile -Path (Join-Path $FixtureDir 'run2-results.json')
        )
        $script:Md = New-MarkdownSummary -Aggregate (Get-AggregatedResults -Results $AllResults) -FileCount 2
    }

    It 'renders the totals table with exact values' {
        $Md | Should -Match '\| Total tests \| 8 \|'
        $Md | Should -Match '\| Passed \| 3 \|'
        $Md | Should -Match '\| Failed \| 3 \|'
        $Md | Should -Match '\| Skipped \| 2 \|'
        $Md | Should -Match '\| Duration \| 2\.95s \|'
    }

    It 'lists flaky tests with pass/fail counts' {
        $Md | Should -Match 'Flaky Tests \(1\)'
        $Md | Should -Match '\| CalculatorSuite \| flaky network call \| 1 \| 1 \|'
    }

    It 'lists failed tests' {
        $Md | Should -Match 'Failed Tests \(2\)'
        $Md | Should -Match '\| CalculatorSuite \| beta divides by zero \| 2 \|'
    }

    It 'reports an overall FAILING status when there are failures' {
        $Md | Should -Match 'Overall status:.*FAILING'
    }

    It 'reports PASSING and no flaky tests for a clean run' {
        $clean = @(
            [pscustomobject]@{ Suite='S'; Name='ok'; Result='passed'; Duration=1.0; SourceFile='a.xml' }
        )
        $md = New-MarkdownSummary -Aggregate (Get-AggregatedResults -Results $clean) -FileCount 1
        $md | Should -Match 'Overall status:.*PASSING'
        $md | Should -Match 'No flaky tests detected'
        $md | Should -Not -Match 'Failed Tests \('
    }
}

Describe 'Invoke-TestResultsAggregator.ps1 (entry script)' {

    BeforeAll {
        $script:ScriptPath = Join-Path $PSScriptRoot '..' '..' 'Invoke-TestResultsAggregator.ps1'
    }

    It 'aggregates a directory of result files and writes the markdown summary' {
        $out = Join-Path $TestDrive 'summary.md'
        & $ScriptPath -Path $FixtureDir -OutputPath $out

        Test-Path $out | Should -BeTrue
        $md = Get-Content $out -Raw
        # 3 fixture files in tests/fixtures: run1 xml (4) + error xml (1) + run2 json (4) = 9
        $md | Should -Match '\| Total tests \| 9 \|'
        $md | Should -Match '\| CalculatorSuite \| flaky network call \| 1 \| 1 \|'
    }

    It 'throws a meaningful error when no result files are found' {
        $emptyDir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        { & $ScriptPath -Path $emptyDir -OutputPath (Join-Path $TestDrive 'x.md') } |
            Should -Throw '*No test result files*'
    }

    It 'throws a meaningful error for a nonexistent input path' {
        { & $ScriptPath -Path (Join-Path $TestDrive 'missing-dir') -OutputPath (Join-Path $TestDrive 'y.md') } |
            Should -Throw '*not found*'
    }
}
