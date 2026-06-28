# Pester tests for the Test Results Aggregator.
# Written test-first (red/green TDD): each Describe block was added as a failing
# test before the corresponding function existed in TestResultsAggregator.ps1.

BeforeAll {
    # Dot-source the implementation under test.
    . "$PSScriptRoot/TestResultsAggregator.ps1"

    # Fixtures live alongside the tests so they can be referenced from CI too.
    $script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'ConvertFrom-JUnitXml' {
    It 'parses a JUnit XML file into normalized test result objects' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $script:FixtureDir 'run1-junit.xml')

        $results | Should -Not -BeNullOrEmpty
        # The first fixture has 4 testcases: 3 passed, 1 failed.
        $results.Count | Should -Be 4
    }

    It 'normalizes status to passed/failed/skipped' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $script:FixtureDir 'run1-junit.xml')

        ($results | Where-Object Status -eq 'passed').Count  | Should -Be 3
        ($results | Where-Object Status -eq 'failed').Count  | Should -Be 1
        ($results | Where-Object Status -eq 'skipped').Count | Should -Be 0
    }

    It 'captures the test name, suite and duration' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $script:FixtureDir 'run1-junit.xml')
        $login = $results | Where-Object Name -eq 'test_login'

        $login.Suite    | Should -Be 'AuthSuite'
        $login.Status   | Should -Be 'passed'
        $login.Duration | Should -BeGreaterThan 0
    }

    It 'treats <error> elements as failed' {
        $results = ConvertFrom-JUnitXml -Path (Join-Path $script:FixtureDir 'run2-junit.xml')
        $errored = $results | Where-Object Name -eq 'test_checkout'
        $errored.Status | Should -Be 'failed'
    }

    It 'throws a meaningful error when the file does not exist' {
        { ConvertFrom-JUnitXml -Path (Join-Path $script:FixtureDir 'does-not-exist.xml') } |
            Should -Throw '*not found*'
    }
}

Describe 'ConvertFrom-TestResultJson' {
    It 'parses a JSON file into normalized test result objects' {
        $results = ConvertFrom-TestResultJson -Path (Join-Path $script:FixtureDir 'run3-results.json')
        $results.Count | Should -Be 4
    }

    It 'normalizes status values from JSON' {
        $results = ConvertFrom-TestResultJson -Path (Join-Path $script:FixtureDir 'run3-results.json')
        ($results | Where-Object Status -eq 'passed').Count  | Should -Be 2
        ($results | Where-Object Status -eq 'failed').Count  | Should -Be 1
        ($results | Where-Object Status -eq 'skipped').Count | Should -Be 1
    }

    It 'throws a meaningful error on malformed JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{ this is not valid json'
        { ConvertFrom-TestResultJson -Path $bad } | Should -Throw '*Failed to parse*'
    }
}

Describe 'Import-TestResultFile' {
    It 'dispatches XML files to the JUnit parser' {
        $results = Import-TestResultFile -Path (Join-Path $script:FixtureDir 'run1-junit.xml')
        $results.Count | Should -Be 4
    }

    It 'dispatches JSON files to the JSON parser' {
        $results = Import-TestResultFile -Path (Join-Path $script:FixtureDir 'run3-results.json')
        $results.Count | Should -Be 4
    }

    It 'throws on an unsupported extension' {
        $txt = Join-Path $TestDrive 'foo.txt'
        Set-Content -Path $txt -Value 'hello'
        { Import-TestResultFile -Path $txt } | Should -Throw '*Unsupported*'
    }
}

Describe 'Get-TestResultSummary' {
    It 'computes totals across a result set' {
        $results = @(
            [pscustomobject]@{ Name='a'; Suite='S'; Status='passed';  Duration=1.0 }
            [pscustomobject]@{ Name='b'; Suite='S'; Status='failed';  Duration=2.0 }
            [pscustomobject]@{ Name='c'; Suite='S'; Status='skipped'; Duration=0.0 }
            [pscustomobject]@{ Name='d'; Suite='S'; Status='passed';  Duration=0.5 }
        )
        $summary = Get-TestResultSummary -Results $results

        $summary.Total    | Should -Be 4
        $summary.Passed   | Should -Be 2
        $summary.Failed   | Should -Be 1
        $summary.Skipped  | Should -Be 1
        $summary.Duration | Should -Be 3.5
    }

    It 'returns zeroed totals for an empty set' {
        $summary = Get-TestResultSummary -Results @()
        $summary.Total    | Should -Be 0
        $summary.Duration | Should -Be 0
    }
}

Describe 'Get-FlakyTests' {
    It 'identifies tests that passed in some runs and failed in others' {
        $results = @(
            [pscustomobject]@{ Name='flaky';  Suite='S'; Status='passed'; Duration=1 }
            [pscustomobject]@{ Name='flaky';  Suite='S'; Status='failed'; Duration=1 }
            [pscustomobject]@{ Name='stable'; Suite='S'; Status='passed'; Duration=1 }
            [pscustomobject]@{ Name='stable'; Suite='S'; Status='passed'; Duration=1 }
        )
        $flaky = Get-FlakyTests -Results $results

        $flaky.Count | Should -Be 1
        $flaky[0].Name        | Should -Be 'flaky'
        $flaky[0].PassedCount | Should -Be 1
        $flaky[0].FailedCount | Should -Be 1
    }

    It 'does not flag a consistently failing test as flaky' {
        $results = @(
            [pscustomobject]@{ Name='broken'; Suite='S'; Status='failed'; Duration=1 }
            [pscustomobject]@{ Name='broken'; Suite='S'; Status='failed'; Duration=1 }
        )
        (Get-FlakyTests -Results $results).Count | Should -Be 0
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $script:results = @(
            [pscustomobject]@{ Name='flaky';  Suite='S'; Status='passed'; Duration=1 }
            [pscustomobject]@{ Name='flaky';  Suite='S'; Status='failed'; Duration=1 }
            [pscustomobject]@{ Name='ok';     Suite='S'; Status='passed'; Duration=2 }
            [pscustomobject]@{ Name='skip';   Suite='S'; Status='skipped';Duration=0 }
        )
        $script:md = New-MarkdownSummary -Results $script:results
    }

    It 'includes a totals table with the computed numbers' {
        $script:md | Should -Match '## Test Results Summary'
        $script:md | Should -Match '\| Passed \|'
        $script:md | Should -Match '2'   # 2 passed
    }

    It 'includes a flaky tests section listing the flaky test' {
        $script:md | Should -Match 'Flaky Tests'
        $script:md | Should -Match 'flaky'
    }

    It 'reports a clean run when there are no flaky tests' {
        $clean = @([pscustomobject]@{ Name='ok'; Suite='S'; Status='passed'; Duration=1 })
        $md = New-MarkdownSummary -Results $clean
        $md | Should -Match 'No flaky tests detected'
    }
}

Describe 'Invoke-TestResultsAggregator (end to end)' {
    It 'aggregates all fixtures and writes a markdown file' {
        $out = Join-Path $TestDrive 'summary.md'
        $md = Invoke-TestResultsAggregator -Path $script:FixtureDir -OutputPath $out

        Test-Path $out | Should -Be $true
        $md | Should -Match '## Test Results Summary'
        # Across all three fixtures, 'test_login' is flaky (passes in run1, fails in run2).
        $md | Should -Match 'test_login'
    }

    It 'throws when no result files are found' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Invoke-TestResultsAggregator -Path $empty -OutputPath (Join-Path $TestDrive 'x.md') } |
            Should -Throw '*No test result files*'
    }
}
