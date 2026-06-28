# Pester tests for the Test Results Aggregator module.
# Developed with red/green TDD: each Describe block corresponds to a unit of
# functionality that was first written as a failing test, then implemented.

BeforeAll {
    # Import the module under test. $PSScriptRoot is the tests/ directory, so
    # the module lives one level up in src/.
    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/TestResultsAggregator.psm1'
    Import-Module $ModulePath -Force

    $FixtureDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'fixtures'
}

Describe 'Import-JUnitResult' {
    It 'parses passed, failed, and skipped test cases from a JUnit XML file' {
        $path = Join-Path $FixtureDir 'run1-junit.xml'
        $results = Import-JUnitResult -Path $path

        # Fixture run1 contains 4 test cases across one suite.
        $results.Count | Should -Be 4

        $login = $results | Where-Object { $_.Name -eq 'Test_Login' }
        $login.Status   | Should -Be 'Passed'
        $login.Suite    | Should -Be 'AuthSuite'
        $login.Duration | Should -Be 0.5

        ($results | Where-Object { $_.Status -eq 'Failed' }).Name  | Should -Be 'Test_Checkout'
        ($results | Where-Object { $_.Status -eq 'Skipped' }).Name | Should -Be 'Test_Legacy'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-JUnitResult -Path 'does-not-exist.xml' } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws a meaningful error when the XML is malformed' {
        $bad = Join-Path $TestDrive 'bad.xml'
        Set-Content -Path $bad -Value '<testsuites><testsuite>'  # unclosed tags
        { Import-JUnitResult -Path $bad } | Should -Throw -ExpectedMessage '*Failed to parse JUnit XML*'
    }
}

Describe 'Import-JsonResult' {
    It 'parses test cases from a JSON results file' {
        $path = Join-Path $FixtureDir 'run2-results.json'
        $results = Import-JsonResult -Path $path

        $results.Count | Should -Be 4

        $checkout = $results | Where-Object { $_.Name -eq 'Test_Checkout' }
        $checkout.Status   | Should -Be 'Passed'   # this run it passed (flaky vs run1)
        $checkout.Suite    | Should -Be 'ShopSuite'
        $checkout.Duration | Should -Be 1.2
    }

    It 'throws a meaningful error when the JSON is malformed' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $bad -Value '{ this is not json'
        { Import-JsonResult -Path $bad } | Should -Throw -ExpectedMessage '*Failed to parse JSON*'
    }
}

Describe 'Import-TestResultFile' {
    It 'dispatches to the JUnit parser for .xml files' {
        $path = Join-Path $FixtureDir 'run1-junit.xml'
        (Import-TestResultFile -Path $path).Count | Should -Be 4
    }

    It 'dispatches to the JSON parser for .json files' {
        $path = Join-Path $FixtureDir 'run2-results.json'
        (Import-TestResultFile -Path $path).Count | Should -Be 4
    }

    It 'throws for an unsupported file extension' {
        $bad = Join-Path $TestDrive 'results.txt'
        Set-Content -Path $bad -Value 'nope'
        { Import-TestResultFile -Path $bad } | Should -Throw -ExpectedMessage '*Unsupported*'
    }
}

Describe 'Get-TestAggregate' {
    BeforeAll {
        # Build deterministic in-memory results spanning two runs so the
        # aggregation logic is tested independently of file parsing.
        $run1 = @(
            [pscustomobject]@{ Name = 'Test_A'; Suite = 'S'; Status = 'Passed'; Duration = 1.0 }
            [pscustomobject]@{ Name = 'Test_B'; Suite = 'S'; Status = 'Failed'; Duration = 2.0 }
            [pscustomobject]@{ Name = 'Test_C'; Suite = 'S'; Status = 'Skipped'; Duration = 0.0 }
        )
        $run2 = @(
            [pscustomobject]@{ Name = 'Test_A'; Suite = 'S'; Status = 'Passed'; Duration = 1.0 }
            [pscustomobject]@{ Name = 'Test_B'; Suite = 'S'; Status = 'Passed'; Duration = 2.5 }  # flaky
        )
        $script:agg = Get-TestAggregate -Results ($run1 + $run2)
    }

    It 'computes total result counts across all runs' {
        $agg.Total   | Should -Be 5
        $agg.Passed  | Should -Be 3
        $agg.Failed  | Should -Be 1
        $agg.Skipped | Should -Be 1
    }

    It 'sums the total duration across all runs' {
        $agg.Duration | Should -Be 6.5
    }

    It 'identifies flaky tests (passed in some runs, failed in others)' {
        $agg.Flaky.Count | Should -Be 1
        $agg.Flaky[0]    | Should -Be 'S.Test_B'
    }

    It 'does not flag consistently-passing tests as flaky' {
        $agg.Flaky | Should -Not -Contain 'S.Test_A'
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $results = @(
            [pscustomobject]@{ Name = 'Test_A'; Suite = 'S'; Status = 'Passed'; Duration = 1.0 }
            [pscustomobject]@{ Name = 'Test_B'; Suite = 'S'; Status = 'Failed'; Duration = 2.0 }
            [pscustomobject]@{ Name = 'Test_B'; Suite = 'S'; Status = 'Passed'; Duration = 2.0 }
        )
        $agg = Get-TestAggregate -Results $results
        $script:md = New-MarkdownSummary -Aggregate $agg
    }

    It 'includes a summary header' {
        $md | Should -Match '# Test Results Summary'
    }

    It 'includes a totals table with the computed numbers' {
        $md | Should -Match '\| Passed \| 2 \|'
        $md | Should -Match '\| Failed \| 1 \|'
        $md | Should -Match '\| Total \| 3 \|'
    }

    It 'lists flaky tests in their own section' {
        $md | Should -Match '## Flaky Tests'
        $md | Should -Match 'S\.Test_B'
    }

    It 'reports a clean bill when there are no flaky tests' {
        $clean = Get-TestAggregate -Results @(
            [pscustomobject]@{ Name = 'Test_A'; Suite = 'S'; Status = 'Passed'; Duration = 1.0 }
        )
        (New-MarkdownSummary -Aggregate $clean) | Should -Match 'No flaky tests detected'
    }
}

Describe 'Invoke-TestResultsAggregation (end-to-end)' {
    It 'aggregates every fixture file in a directory and writes a markdown file' {
        $out = Join-Path $TestDrive 'summary.md'
        $agg = Invoke-TestResultsAggregation -InputPath $FixtureDir -OutputPath $out

        Test-Path $out | Should -BeTrue

        # Across the two fixture runs, Test_Checkout fails in run1 and passes in
        # run2, so it must be reported as flaky end-to-end.
        $agg.Flaky | Should -Contain 'ShopSuite.Test_Checkout'

        (Get-Content $out -Raw) | Should -Match '# Test Results Summary'
    }

    It 'throws when the input path contains no supported result files' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Invoke-TestResultsAggregation -InputPath $empty -OutputPath (Join-Path $TestDrive 'x.md') } |
            Should -Throw -ExpectedMessage '*No supported test result files*'
    }
}
