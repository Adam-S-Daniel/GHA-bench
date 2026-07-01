# Pester tests for the test-results aggregator.
# Run with: Invoke-Pester ./Tests/TestResultsAggregator.Tests.ps1

BeforeAll {
    # Dot-source the script so its functions are available without triggering
    # the CLI entry point (guarded by $MyInvocation.InvocationName below).
    . "$PSScriptRoot/../TestResultsAggregator.ps1"
    $FixturesPath = "$PSScriptRoot/../fixtures"
}

Describe 'Import-JUnitXmlResult' {
    It 'parses passed, failed, and skipped test cases with durations' {
        $cases = Import-JUnitXmlResult -Path "$FixturesPath/simple.junit.xml"

        $cases.Count | Should -Be 3

        $add = $cases | Where-Object Name -eq 'test_add'
        $add.Status | Should -Be 'Passed'
        $add.Duration | Should -Be 0.1

        $subtract = $cases | Where-Object Name -eq 'test_subtract'
        $subtract.Status | Should -Be 'Failed'
        $subtract.Duration | Should -Be 0.2

        $divide = $cases | Where-Object Name -eq 'test_divide'
        $divide.Status | Should -Be 'Skipped'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-JUnitXmlResult -Path "$FixturesPath/does-not-exist.xml" } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed XML' {
        { Import-JUnitXmlResult -Path "$FixturesPath/malformed.xml" } |
            Should -Throw
    }
}

Describe 'Import-JsonTestResult' {
    It 'parses passed and failed test cases with durations' {
        $cases = Import-JsonTestResult -Path "$FixturesPath/matrix/run3.results.json"

        $cases.Count | Should -Be 3

        $login = $cases | Where-Object Name -eq 'test_login'
        $login.Status | Should -Be 'Passed'
        $login.Duration | Should -Be 0.55

        $newFeature = $cases | Where-Object Name -eq 'test_new_feature'
        $newFeature.Status | Should -Be 'Failed'
    }

    It 'throws a meaningful error when the file does not exist' {
        { Import-JsonTestResult -Path "$FixturesPath/does-not-exist.json" } |
            Should -Throw '*not found*'
    }

    It 'throws a meaningful error for malformed JSON' {
        { Import-JsonTestResult -Path "$FixturesPath/malformed.json" } |
            Should -Throw
    }
}

Describe 'Import-TestResultFile' {
    It 'dispatches .xml files to the JUnit parser' {
        $cases = Import-TestResultFile -Path "$FixturesPath/simple.junit.xml"
        $cases.Count | Should -Be 3
    }

    It 'dispatches .json files to the JSON parser' {
        $cases = Import-TestResultFile -Path "$FixturesPath/matrix/run3.results.json"
        $cases.Count | Should -Be 3
    }

    It 'throws a meaningful error for unsupported extensions' {
        { Import-TestResultFile -Path "$FixturesPath/unsupported.txt" } |
            Should -Throw '*Unsupported*'
    }
}

Describe 'Get-AggregatedTestResults' {
    BeforeAll {
        $script:Aggregate = Get-AggregatedTestResults -Path @(
            "$FixturesPath/matrix/run1.junit.xml",
            "$FixturesPath/matrix/run2.junit.xml",
            "$FixturesPath/matrix/run3.results.json"
        )
    }

    It 'computes total counts across all files' {
        $Aggregate.TotalTests | Should -Be 9
        $Aggregate.TotalPassed | Should -Be 4
        $Aggregate.TotalFailed | Should -Be 4
        $Aggregate.TotalSkipped | Should -Be 1
    }

    It 'sums duration across all files' {
        $Aggregate.TotalDuration | Should -Be 4.7
    }

    It 'identifies flaky tests that pass in one run and fail in another' {
        $Aggregate.FlakyTests.Count | Should -Be 1
        $Aggregate.FlakyTests[0].Name | Should -Be 'test_login'
    }

    It 'does not flag tests that only fail or only pass across runs' {
        $Aggregate.FlakyTests.Name | Should -Not -Contain 'test_logout'
        $Aggregate.FlakyTests.Name | Should -Not -Contain 'test_payment'
    }

    It 'throws a meaningful error when given an empty file list' {
        { Get-AggregatedTestResults -Path @() } | Should -Throw '*No test result files*'
    }
}

Describe 'New-MarkdownSummary' {
    BeforeAll {
        $script:Aggregate = Get-AggregatedTestResults -Path @(
            "$FixturesPath/matrix/run1.junit.xml",
            "$FixturesPath/matrix/run2.junit.xml",
            "$FixturesPath/matrix/run3.results.json"
        )
        $script:Markdown = New-MarkdownSummary -Aggregate $Aggregate
    }

    It 'includes a summary heading' {
        $Markdown | Should -Match '# Test Results Summary'
    }

    It 'includes total, passed, failed, and skipped counts' {
        $Markdown | Should -Match '\| Total \| 9 \|'
        $Markdown | Should -Match '\| Passed \| 4 \|'
        $Markdown | Should -Match '\| Failed \| 4 \|'
        $Markdown | Should -Match '\| Skipped \| 1 \|'
    }

    It 'includes the flaky tests section with the flaky test name' {
        $Markdown | Should -Match '## Flaky Tests'
        $Markdown | Should -Match 'test_login'
    }

    It 'reports overall status as FAILURE when there are failed tests' {
        $Markdown | Should -Match '\*\*Overall Status:\*\* FAILURE'
    }
}
